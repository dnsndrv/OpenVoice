# OpenVoice

Аналог [Voice Ink](https://github.com/Beingpax/VoiceInk) — нативное macOS-приложение для системной голосовой диктовки. Жмёшь горячую клавишу, говоришь, ещё раз — расшифрованный текст вставляется в активное приложение. Полностью локально, оффлайн, приватно.

- Распознавание речи через [whisper.cpp](https://github.com/ggml-org/whisper.cpp) с Metal-ускорением на Apple Silicon
- Меню-бар приложение, никаких окон в Dock
- Глобальный хоткей: одиночный модификатор без других клавиш (правый ⌘ по умолчанию) через `CGEventTap`
- Вставка через системный pasteboard с восстановлением старого содержимого
- История транскрипций (SwiftData)

## Требования

- macOS 14+ (тестировалось на 15.7)
- Xcode 16+
- Apple Silicon рекомендуется (Metal-ускорение). На Intel будет работать через CPU+Accelerate, но медленнее

## Сборка и установка

```bash
git clone https://github.com/dnsndrv/OpenVoice.git
cd OpenVoice
bash scripts/install.sh
```

Скрипт делает:

1. Создаёт постоянный self-signed сертификат `OpenVoice Local Signer` в твоём login keychain (один раз). При первом запуске macOS спросит пароль учётной записи через GUI-диалог — нужно для разблокировки доступа codesign к ключу.
2. Собирает Release-конфигурацию проекта.
3. Подписывает приложение этим сертификатом и кладёт в `~/Applications/OpenVoice.app`.
4. Запускает приложение.

Зачем self-signed: macOS TCC привязывает разрешения (Microphone, Accessibility) к **designated requirement** подписи. У ad-hoc подписи это `cdhash`, который меняется на каждой пересборке → разрешения слетают. С постоянным сертификатом requirement содержит хеш сертификата → выданные один раз разрешения сохраняются между пересборками.

## Первый запуск

1. macOS попросит доступ к **микрофону** — Allow.
2. Открой иконку микрофона в menu bar → **Настройки → Разрешения → «Открыть настройки»** → добавь `OpenVoice` в список Accessibility (drag-and-drop из `~/Applications/` или через `+`). Это нужно для глобального перехвата хоткея.
3. Открой **Настройки → Модель** → выбери `small` (~460 MB) → **Скачать**. Модель кэшируется в `~/Library/Application Support/OpenVoice/models/`.

После этого:
- Поставь курсор в любое текстовое поле.
- Нажми правый ⌘ — появится плавающее окно записи с волной уровня.
- Говоришь.
- Нажми правый ⌘ ещё раз — через ~0.5–1 секунды расшифрованный текст вставится.

## Архитектура

```
OpenVoice/                     # Xcode проект
├── App/                       # AppDelegate, AppCoordinator
├── Audio/                     # AVAudioEngine + AVAudioConverter → 16 kHz mono PCM
├── Transcription/             # WhisperBridge (C API), WhisperTranscriber (actor)
├── Injection/                 # TextInjector — pasteboard + CGEvent Cmd+V
├── Hotkey/                    # ModifierHotkeyMonitor — CGEventTap, single-modifier detect
├── Coordinator/               # RecordingCoordinator — стейт-машина idle→recording→…→idle
├── Model/                     # SwiftData история, ModelManager (download)
├── Settings/                  # SettingsStore (@AppStorage)
├── UI/                        # MenuBarView, RecordingHUD, History, Settings, Diagnostics
└── Util/                      # Logger

Packages/Whisper/              # Локальный SPM-пакет: whisper.cpp v1.7.0 + Metal
├── Sources/whisper/           # ggml + whisper.cpp (CPU + Accelerate)
└── Sources/whisper_metal/     # ggml-metal.m + .metal (изолировано от C++)
```

Локальный пакет собирает whisper.cpp без `unsafeFlags` (которые upstream Package.swift использовал и блокировал линковку в app target). ObjC-код Metal-бэкенда выделен в отдельный target с `-fno-objc-arc` (он использует ручной retain/release).

## Известные ограничения

- На Intel-Mac будет медленнее без Metal.
- Не работает в окнах с песочницей, которые игнорируют события вне своего ввода (но Cmd+V обычно проходит везде).
- Distinguishing left/right Command делается через `NX_DEVICERCMDKEYMASK` device flag из CGEvent — на нестандартных клавиатурах может не работать.
- Disk Sandbox выключен (нужен для `CGEvent.post` в чужие приложения), поэтому в Mac App Store не положишь без переделки.

## Лицензия

MIT для нашего кода. whisper.cpp под MIT.
