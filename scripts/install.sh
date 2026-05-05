#!/usr/bin/env bash
# Сборка OpenVoice и установка в ~/Applications/OpenVoice.app, подписанная
# постоянным self-signed сертификатом из login keychain.
#
# Зачем self-signed: macOS TCC привязывает разрешения (Microphone /
# Accessibility) к designated requirement подписи. Для ad-hoc подписи это
# cdhash бинарника, который меняется при каждой пересборке — поэтому
# разрешения сбрасываются. Для подписи сертификатом requirement содержит
# хеш сертификата, который стабилен → разрешения сохраняются вечно.
#
# Сертификат создаётся один раз и хранится в login.keychain под именем
# `OpenVoice Local Signer`. Потерять его не страшно — этот скрипт пересоздаст.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ="$PROJECT_DIR/OpenVoice/OpenVoice.xcodeproj"
SCHEME="OpenVoice"          # Xcode scheme name (kept after VibeVoice rebrand)
APP_NAME="VibeVoice.app"    # produced .app bundle (PRODUCT_NAME=VibeVoice)
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/$APP_NAME"
# Persistent self-signed signing identity. Name kept legacy on purpose:
# changing it would invalidate the designated requirement of all existing
# TCC permission grants on the developer's machine.
SIGN_IDENTITY="OpenVoice Local Signer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# ------------------------------------------------------------------
# 1. Убедиться что в keychain есть сертификат для подписи.
# ------------------------------------------------------------------
cert_sha1() {
    security find-certificate -c "$SIGN_IDENTITY" -Z "$KEYCHAIN" 2>/dev/null \
        | awk -F': ' '/SHA-1/ {print $2; exit}'
}

ensure_signing_identity() {
    if [[ -n "$(cert_sha1)" ]]; then
        return 0
    fi

    echo "▶ Создаю сертификат '$SIGN_IDENTITY' в login.keychain (один раз)…"
    local tmp
    tmp="$(mktemp -d)"
    trap "rm -rf '$tmp'" RETURN

    cat >"$tmp/openssl.cnf" <<EOF
[req]
distinguished_name = req_dn
req_extensions = v3_req
prompt = no

[req_dn]
CN = $SIGN_IDENTITY

[v3_req]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning,1.2.840.113635.100.6.1.13
EOF

    /usr/bin/openssl req \
        -x509 \
        -newkey rsa:2048 \
        -nodes \
        -days 7300 \
        -keyout "$tmp/key.pem" \
        -out "$tmp/cert.pem" \
        -config "$tmp/openssl.cnf" \
        -extensions v3_req \
        2>/dev/null

    /usr/bin/openssl pkcs12 \
        -export \
        -out "$tmp/bundle.p12" \
        -inkey "$tmp/key.pem" \
        -in "$tmp/cert.pem" \
        -name "$SIGN_IDENTITY" \
        -passout pass:openvoice \
        -macalg SHA1 \
        2>/dev/null

    # Импорт в login keychain. -A разрешает любым приложениям читать
    # ключ без запроса пароля; -T /usr/bin/codesign явно даёт доступ
    # codesign'у.
    security import "$tmp/bundle.p12" \
        -k "$KEYCHAIN" \
        -P openvoice \
        -A \
        -T /usr/bin/codesign \
        -T /usr/bin/security \
        >/dev/null

    # Делаем ключ доступным codesign'у без интерактивного диалога.
    # Этот шаг требует пароль от login keychain (= пароль учётной записи macOS).
    # Запрашиваем через GUI-диалог macOS — работает и в Terminal, и без TTY.
    echo "▶ Сейчас macOS попросит пароль учётной записи (нужен один раз для разблокировки ключа подписи)…"
    KEYCHAIN_PASSWORD="$(/usr/bin/osascript -e 'display dialog "OpenVoice install: enter your macOS password to allow codesign to use the local signing key.\n\nThe password is not stored." default answer "" with hidden answer with title "OpenVoice Setup"' -e 'text returned of result' 2>/dev/null)" || {
        echo "Пользователь отменил ввод пароля" >&2
        exit 1
    }

    if ! security set-key-partition-list \
            -S apple-tool:,apple:,codesign:,unsigned: \
            -s \
            -k "$KEYCHAIN_PASSWORD" \
            "$KEYCHAIN" \
            >/dev/null 2>&1; then
        echo "ОШИБКА: set-key-partition-list упал. Возможно, неверный пароль." >&2
        exit 1
    fi
    unset KEYCHAIN_PASSWORD

    if [[ -z "$(cert_sha1)" ]]; then
        echo "ОШИБКА: сертификат не появился после импорта" >&2
        exit 1
    fi
    echo "✓ Сертификат создан"
}

# ------------------------------------------------------------------
# 2. Сборка и установка.
# ------------------------------------------------------------------
if [[ ! -d "$XCODEPROJ" ]]; then
    echo "Не найден $XCODEPROJ" >&2
    exit 1
fi

ensure_signing_identity

mkdir -p "$DEST_DIR"

echo "▶ Завершаю запущенные копии VibeVoice…"
osascript -e 'tell application "VibeVoice" to quit' 2>/dev/null || true
osascript -e 'tell application "OpenVoice" to quit' 2>/dev/null || true
pkill -x VibeVoice 2>/dev/null || true
pkill -x OpenVoice 2>/dev/null || true
sleep 0.5

echo "▶ Build VibeVoice (Release)…"
DERIVED="$(mktemp -d)"
trap 'rm -rf "$DERIVED"' EXIT

xcodebuild \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS' \
    build \
    > "$DERIVED/build.log" 2>&1 || {
        echo "Сборка упала. Лог: $DERIVED/build.log" >&2
        tail -40 "$DERIVED/build.log" >&2
        exit 1
    }

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Не нашёл собранный $APP_NAME" >&2
    exit 1
fi

echo "▶ Install $DEST"
if [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
fi
# Подчистить устаревший OpenVoice.app (ребрендинг VibeVoice).
if [[ -d "$DEST_DIR/OpenVoice.app" ]]; then
    rm -rf "$DEST_DIR/OpenVoice.app"
fi
ditto "$BUILT_APP" "$DEST"

SHA1="$(cert_sha1)"
if [[ -z "$SHA1" ]]; then
    echo "Не удалось найти SHA1 сертификата" >&2
    exit 1
fi

echo "▶ Sign with '$SIGN_IDENTITY' (SHA1=$SHA1)"
# Подписываем по SHA1 — это работает без явного добавления сертификата
# в codesigning trust policy (т.е. без sudo).
codesign \
    --force \
    --deep \
    --sign "$SHA1" \
    --options=runtime \
    --entitlements "$PROJECT_DIR/OpenVoice/OpenVoice/OpenVoice.entitlements" \
    "$DEST"

codesign --verify --verbose=2 "$DEST" 2>&1 | tail -5

echo
echo "✅ Установлено: $DEST"
echo
echo "При ПЕРВОМ запуске после смены сертификата выдай заново:"
echo "  • Microphone (диалог сам появится)"
echo "  • Accessibility (System Settings → Privacy → Accessibility)"
echo "Дальше — пересборки этим скриптом разрешения НЕ сбросят."
echo

echo "▶ Запускаю $DEST"
open "$DEST"
