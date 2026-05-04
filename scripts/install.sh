#!/usr/bin/env bash
# Сборка OpenVoice и установка в ~/Applications/OpenVoice.app со стабильной
# ad-hoc подписью. Это единственный надёжный способ работать с TCC
# (Accessibility / Microphone) во время разработки: у приложения в
# постоянном пути и со стабильным bundle id разрешения не сбрасываются.
#
# Использование:
#   bash scripts/install.sh
#
# Рекомендуемый workflow:
#   1. Запускай этот скрипт после изменений
#   2. Закрой работающую копию OpenVoice (через menu-bar «Выйти»)
#   3. Запусти ~/Applications/OpenVoice.app (через Spotlight: «OpenVoice»)
#   4. Разрешения, которые выдал один раз, продолжают работать

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ="$PROJECT_DIR/OpenVoice/OpenVoice.xcodeproj"
DEST_DIR="$HOME/Applications"
APP_NAME="OpenVoice.app"
DEST="$DEST_DIR/$APP_NAME"

if [[ ! -d "$XCODEPROJ" ]]; then
    echo "Не найден $XCODEPROJ" >&2
    exit 1
fi

mkdir -p "$DEST_DIR"

echo "▶ Build OpenVoice (Release)…"
DERIVED="$(mktemp -d)"
trap 'rm -rf "$DERIVED"' EXIT

xcodebuild \
    -project "$XCODEPROJ" \
    -scheme OpenVoice \
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
    echo "Не нашёл собранный $APP_NAME в $BUILT_APP" >&2
    exit 1
fi

echo "▶ Install $DEST"
if [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
fi
ditto "$BUILT_APP" "$DEST"

# Стабильная ad-hoc подпись на финальном бинарнике в стабильном пути.
codesign --force --deep --sign - "$DEST"

echo
echo "✅ Установлено в $DEST"
echo
echo "Дальше:"
echo "  1. Если открыт OpenVoice — выйди через menu-bar"
echo "  2. Запусти из Spotlight: open '$DEST'"
echo "  3. Выдай Microphone и Accessibility ОДИН РАЗ — больше не будет сбрасываться"

# Откроем приложение автоматически
echo
echo "▶ Запускаю $DEST"
open "$DEST"
