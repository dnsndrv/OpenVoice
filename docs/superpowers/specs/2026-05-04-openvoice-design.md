# VibeVoice — дизайн

**Дата:** 2026-05-04
**Статус:** утверждён, готов к плану реализации

## Цель

Нативное macOS-приложение для системной голосовой диктовки. Пользователь нажимает глобальный хоткей, говорит, нажимает ещё раз — расшифрованный текст вставляется в активное поле любого приложения. Полностью локально, оффлайн, приватно.

## Стек

- **Платформа:** macOS 14+ (Sonoma), Swift 5.9+, SwiftUI, AppKit (для menu bar и HUD)
- **Распознавание:** [whisper.cpp](https://github.com/ggerganov/whisper.cpp) через Swift Package, Metal-ускорение
- **Модель по умолчанию:** `ggml-small.bin` (~244 MB), язык `ru`
- **Хранилище истории:** SwiftData
- **Глобальный хоткей:** свой `ModifierHotkeyMonitor` поверх `NSEvent.addGlobalMonitorForEvents(.flagsChanged)` — стандартные библиотеки (KeyboardShortcuts) не поддерживают modifier-only хоткеи
- **Аудио:** AVFoundation / `AVAudioEngine`
- **Распространение:** menu bar app (LSUIElement), без App Sandbox

## Поведение

### Главный сценарий

1. Пользователь нажимает **правый Command** в любом приложении
2. Появляется плавающее окно записи (HUD) с волной уровня и таймером
3. Пользователь говорит
4. Нажимает правый Command ещё раз
5. HUD меняет состояние на «Расшифровка...»
6. Whisper расшифровывает PCM → текст
7. Текст копируется в pasteboard, симулируется `Cmd+V` в активное приложение
8. Старый pasteboard восстанавливается через 500 мс
9. HUD исчезает, запись добавляется в историю

### Edge cases

- **Нет accessibility-разрешения:** HUD остаётся видимым, показывает текст и кнопку «Копировать», без авто-вставки
- **Нет microphone-разрешения:** при попытке записи — alert с кнопкой «Открыть настройки»
- **Модель не скачана:** при первом запуске — onboarding-окно с прогрессом скачивания. Хоткей не работает до завершения
- **Whisper упал / нулевой результат:** HUD показывает ошибку 2 секунды и исчезает; если что-то расшифровалось — сохраняем в историю
- **Хоткей дребезжит (двойное нажатие <150мс):** игнорируем второе

## Архитектура: модули

Каждый модуль имеет одну ответственность и публичный интерфейс, тестируем независимо.

### `AudioRecorder`

- API: `start() throws`, `stop() async -> Data` (16 kHz mono float32 PCM), `levelPublisher: AnyPublisher<Float, Never>` (RMS 0..1, 30 Гц)
- Использует `AVAudioEngine` с tap на `inputNode`. Конвертирует во float32 16 kHz через `AVAudioConverter`
- Зависит только от AVFoundation

### `Transcriber`

- API: `func transcribe(pcm: Data, language: String) async throws -> TranscriptionResult`
- `TranscriptionResult { text: String, segments: [Segment] }`
- Обёртка над whisper.cpp C API. Загружает модель один раз, держит контекст в памяти
- Работает на background `Task.detached(priority: .userInitiated)`
- Зависит от `WhisperKit/whisper.cpp` SPM

### `TextInjector`

- API: `func inject(_ text: String) async throws`
- Алгоритм: сохранить текущий `NSPasteboard.general.string`, положить новый текст, отправить `Cmd+V` через `CGEvent.post(.cghidEventTap)`, через 500 мс восстановить старый pasteboard
- Проверяет accessibility-permission через `AXIsProcessTrustedWithOptions`. Если нет — кидает `TextInjectorError.noAccessibility`

### `ModifierHotkeyMonitor`

- API: `var onTrigger: () -> Void`, `func setKey(_ key: ModifierKey)`, `enum ModifierKey { rightCommand, rightOption, fn, leftControl }`
- Подписка на `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` + локальный монитор для случая, когда наше приложение в фокусе
- Детектирует «нажатие и отпускание» одного модификатора (без других клавиш в течение нажатия) — иначе обычные сочетания типа `Cmd+C` будут срабатывать как триггер
- Дребезг: игнор повторного триггера < 150 мс

### `RecordingCoordinator`

- Стейт-машина: `.idle`, `.recording`, `.transcribing`, `.injecting`, `.error(String)`
- API: `func toggle()`, `@Published var state: State`
- Связывает: `HotkeyMonitor.onTrigger → toggle() → AudioRecorder ↔ Transcriber → HistoryStore → TextInjector`
- Главный объект-координатор, единственный, кто знает про все остальные

### `ModelManager`

- API: `func ensureModel() async throws -> URL`, `var progress: AnyPublisher<Double, Never>`
- Скачивает `ggml-small.bin` с `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin` в `~/Library/Application Support/OpenVoice/models/`
- Проверяет SHA256 (захардкожен константой)
- Поддерживает докачку через `URLSession` с `resumeData`

### `HistoryStore`

- SwiftData-модель `Transcription { id: UUID, text: String, durationSec: Double, createdAt: Date, language: String }`
- API: `func save(_:)` , `func recent(limit: Int) -> [Transcription]`, `func delete(_:)`, `func clear()`

### `Settings`

- `@AppStorage`-обёртки: `hotkeyKey: ModifierKey`, `language: String`, `modelName: String`, `microphoneDeviceID: String?`, `restorePasteboard: Bool`
- Один `SettingsStore: ObservableObject`

## UI

### `MenuBarView` (NSStatusItem + popover)

- Иконка: микрофон (меняется при записи)
- Popover: статус, последние 3 транскрипции, «Открыть историю», «Настройки», «Выход»

### `RecordingHUD` (NSPanel, floating, non-activating)

- Размер ~280×80, позиция: bottom-center экрана с активным окном
- Состояния: запись (волна + таймер + «остановить»), расшифровка (спиннер), ошибка
- Скругление, blur-фон (`NSVisualEffectView`)

### `HistoryWindow` (SwiftUI)

- Список с поиском, копирование одной записи, удаление, очистить всё

### `OnboardingWindow`

- Шаг 1: «Разрешите микрофон» → запрос
- Шаг 2: «Разрешите управление компьютером» (accessibility) → открыть настройки
- Шаг 3: «Скачиваем модель» → прогресс
- Шаг 4: «Готово, попробуй: правый Command, скажи фразу, ещё раз правый Command»

### `SettingsWindow`

- Хоткей: радио (правый Cmd / правый Option / Fn / левый Control)
- Язык: ru / en / auto
- Модель: small / medium (скачать)
- Микрофон: список устройств
- Чекбокс «Восстанавливать pasteboard»

## Файловая структура

```
OpenVoice/
├── OpenVoice.xcodeproj
├── OpenVoice/
│   ├── App/
│   │   ├── OpenVoiceApp.swift          # @main, AppDelegate, LSUIElement
│   │   └── AppCoordinator.swift        # сборка зависимостей
│   ├── Audio/
│   │   └── AudioRecorder.swift
│   ├── Transcription/
│   │   ├── Transcriber.swift
│   │   └── WhisperBridge.swift         # C-API обёртка
│   ├── Injection/
│   │   └── TextInjector.swift
│   ├── Hotkey/
│   │   └── ModifierHotkeyMonitor.swift
│   ├── Coordinator/
│   │   └── RecordingCoordinator.swift
│   ├── Model/
│   │   ├── ModelManager.swift
│   │   ├── HistoryStore.swift
│   │   └── Transcription.swift
│   ├── Settings/
│   │   └── SettingsStore.swift
│   ├── UI/
│   │   ├── MenuBar/MenuBarView.swift
│   │   ├── HUD/RecordingHUD.swift
│   │   ├── History/HistoryWindow.swift
│   │   ├── Onboarding/OnboardingWindow.swift
│   │   └── Settings/SettingsWindow.swift
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Info.plist
│   └── Util/
│       └── Logger.swift
├── OpenVoiceTests/
│   ├── TranscriberTests.swift
│   ├── TextInjectorTests.swift
│   ├── RecordingCoordinatorTests.swift
│   └── ModifierHotkeyMonitorTests.swift
├── Package.swift                       # для SPM-зависимостей
└── README.md
```

## Permissions / Info.plist

- `NSMicrophoneUsageDescription` = «OpenVoice использует микрофон для распознавания речи»
- `LSUIElement` = `true` (без иконки в Dock)
- App Sandbox **выключен** (CGEvent в чужие приложения требует это)
- Hardened Runtime включён, com.apple.security.device.audio-input

## Тестирование

- `**TranscriberTests`:** фиксированный 16 kHz wav («раз два три» на русском) → проверяем, что `text` содержит «два»
- `**TextInjectorTests`:** mock pasteboard provider + mock event poster, проверяем последовательность вызовов
- `**RecordingCoordinatorTests`:** все переходы стейт-машины, отдельно happy path и каждая ошибка
- `**ModifierHotkeyMonitorTests`:** генерируем `flagsChanged` события вручную, проверяем триггер только на одиночное нажатие+отпускание правого Cmd

## Что НЕ входит в первую версию (явно отложено)

- AI-постобработка через LLM
- Кастомный словарь терминов
- Профили (разные хоткеи под разные приложения)
- Поддержка Windows/Linux
- Streaming-транскрипция в реальном времени
- Запись с системного аудио

## Открытые риски

1. **whisper.cpp SPM-сборка под Apple Silicon + Intel:** проверить на ранней стадии. Если не соберётся universal — отказываемся от Intel
2. **Modifier-only хоткей конфликтует с системой:** правый Cmd используется в Spotlight по двойному нажатию у некоторых пользователей. Onboarding должен это упомянуть и предложить смену
3. **Cmd+V не работает в Terminal/iTerm для не-английских раскладок:** fallback — показать текст в HUD с кнопкой копирования

