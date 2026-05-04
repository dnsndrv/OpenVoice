# OpenVoice MVP Implementation Plan

**Goal:** Рабочая end-to-end диктовка на macOS: правый Command → запись → whisper.cpp → вставка в активное приложение, плюс menu bar, история и onboarding.

**Architecture:** Нативное Swift/SwiftUI macOS-приложение. Слабосвязанные модули (Audio / Transcription / Injection / Hotkey) подключаются через `RecordingCoordinator`. whisper.cpp как git submodule, собирается статической библиотекой через target в `.xcodeproj`.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, AVFoundation, SwiftData, whisper.cpp (Metal), XCTest.

**Spec:** `docs/superpowers/specs/2026-05-04-openvoice-design.md`

---

## Phase 0: Скелет проекта

### Task 0.1: Создать Xcode-проект

- Создать `OpenVoice.xcodeproj` через `xcodebuild -create-xcframework` шаблон / руками — macOS App, SwiftUI, deployment target 14.0, bundle id `com.openvoice.app`
- Включить LSUIElement в Info.plist
- Добавить `NSMicrophoneUsageDescription`
- Отключить App Sandbox в entitlements
- Запустить, убедиться, что приложение открывается без иконки в Dock
- Коммит: `chore: scaffold Xcode project`

### Task 0.2: Подключить whisper.cpp

- `git submodule add https://github.com/ggerganov/whisper.cpp Vendor/whisper.cpp`
- Добавить в Xcode-проект статическую библиотеку из `Vendor/whisper.cpp/ggml.c`, `whisper.cpp`, `ggml-metal.m`, заголовки
- Добавить bridging header `OpenVoice-Bridging-Header.h` с `#include "whisper.h"`
- Скомпилировать пустой проект, убедиться, что `whisper_print_system_info` доступен из Swift
- Коммит: `chore: vendor whisper.cpp as static library`

### Task 0.3: Базовая папочная структура и логгер

- Создать папки: `Audio/`, `Transcription/`, `Injection/`, `Hotkey/`, `Coordinator/`, `Model/`, `Settings/`, `UI/{MenuBar,HUD,History,Onboarding,Settings}/`, `Util/`
- `Util/Logger.swift`: `let log = Logger(subsystem: "com.openvoice.app", category: ...)`
- Тест-таргет `OpenVoiceTests`
- Коммит: `chore: project skeleton`

---

## Phase 1: Core модули (TDD)

### Task 1.1: AudioRecorder — захват PCM

**Files:**
- Create: `OpenVoice/Audio/AudioRecorder.swift`
- Test: `OpenVoiceTests/AudioRecorderTests.swift`

- [ ] Тест: после `start()` → `stop()` через 1 сек возвращает `Data` длиной ≈ 16000*4 байт (16kHz float32)
- [ ] Тест: `levelPublisher` шлёт значения в диапазоне [0..1]
- [ ] Реализация через `AVAudioEngine` + `installTap` + `AVAudioConverter` в 16kHz mono float32
- [ ] Коммит

```swift
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var buffer = Data()
    private let levelSubject = PassthroughSubject<Float, Never>()
    var levelPublisher: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)!
        buffer.removeAll()
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcm, _ in
            guard let self else { return }
            let frameCapacity = AVAudioFrameCount(Double(pcm.frameLength) * 16000.0 / inputFormat.sampleRate)
            guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: frameCapacity) else { return }
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                status.pointee = .haveData; return pcm
            }
            if let ptr = out.floatChannelData?[0] {
                let count = Int(out.frameLength)
                self.buffer.append(UnsafeBufferPointer(start: ptr, count: count).withMemoryRebound(to: UInt8.self) { $0 })
                let rms = (0..<count).reduce(Float(0)) { $0 + ptr[$1]*ptr[$1] } / Float(max(count,1))
                self.levelSubject.send(min(1, sqrt(rms)*4))
            }
        }
        try engine.start()
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return buffer
    }
}
```

### Task 1.2: WhisperBridge — обёртка над C-API

**Files:**
- Create: `OpenVoice/Transcription/WhisperBridge.swift`
- Test: `OpenVoiceTests/WhisperBridgeTests.swift` (требует `ggml-tiny.bin` в bundle для теста — или skip если нет)

- [ ] Тест: `WhisperBridge(modelPath:)` не кидает на валидной модели
- [ ] Тест: `transcribe(samples:)` на embedded sample wav возвращает непустой текст
- [ ] Реализация: `whisper_init_from_file_with_params`, `whisper_full_default_params`, лямки на сегменты через `whisper_full_n_segments`/`whisper_full_get_segment_text`
- [ ] Коммит

```swift
final class WhisperBridge {
    private let ctx: OpaquePointer

    init(modelPath: URL) throws {
        var p = whisper_context_default_params()
        p.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelPath.path, p) else {
            throw WhisperError.modelLoadFailed
        }
        self.ctx = ctx
    }
    deinit { whisper_free(ctx) }

    func transcribe(samples: [Float], language: String) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        language.withCString { params.language = $0 }
        params.translate = false
        params.print_progress = false
        params.print_realtime = false
        params.no_context = true
        let result = samples.withUnsafeBufferPointer { ptr in
            whisper_full(ctx, params, ptr.baseAddress, Int32(samples.count))
        }
        guard result == 0 else { throw WhisperError.transcribeFailed(result) }
        let n = whisper_full_n_segments(ctx)
        var out = ""
        for i in 0..<n {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                out += String(cString: cstr)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum WhisperError: Error { case modelLoadFailed, transcribeFailed(Int32) }
}
```

### Task 1.3: Transcriber — высокоуровневый API

**Files:**
- Create: `OpenVoice/Transcription/Transcriber.swift`
- Test: `OpenVoiceTests/TranscriberTests.swift`

- [ ] Тест: `transcribe(pcmData:)` конвертирует `Data` (float32) в `[Float]` и вызывает bridge
- [ ] Тест: вызовы сериализуются (`actor`)
- [ ] Реализация:

```swift
actor Transcriber {
    private var bridge: WhisperBridge?
    func load(model: URL) throws { bridge = try WhisperBridge(modelPath: model) }
    func transcribe(pcm: Data, language: String) throws -> String {
        guard let bridge else { throw TranscriberError.notLoaded }
        let samples: [Float] = pcm.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
        return try bridge.transcribe(samples: samples, language: language)
    }
    enum TranscriberError: Error { case notLoaded }
}
```

### Task 1.4: TextInjector — вставка через Cmd+V

**Files:**
- Create: `OpenVoice/Injection/TextInjector.swift`
- Test: `OpenVoiceTests/TextInjectorTests.swift`

- [ ] Протокол `PasteboardProvider` и `EventPoster` для мокинга
- [ ] Тест: `inject("привет")` сохраняет старый pasteboard, ставит новый, шлёт Cmd+V (V=9), восстанавливает
- [ ] Тест: при отсутствии accessibility — кидает `noAccessibility`
- [ ] Реализация:

```swift
protocol PasteboardProvider: AnyObject {
    var stringValue: String? { get set }
}
protocol EventPoster {
    func postCmdV() throws
}

final class TextInjector {
    private let pasteboard: PasteboardProvider
    private let poster: EventPoster
    private let trustChecker: () -> Bool

    init(pasteboard: PasteboardProvider, poster: EventPoster, trustChecker: @escaping () -> Bool) {
        self.pasteboard = pasteboard; self.poster = poster; self.trustChecker = trustChecker
    }

    func inject(_ text: String, restorePasteboard: Bool = true) async throws {
        guard trustChecker() else { throw InjectorError.noAccessibility }
        let saved = pasteboard.stringValue
        pasteboard.stringValue = text
        try poster.postCmdV()
        if restorePasteboard {
            try? await Task.sleep(nanoseconds: 500_000_000)
            pasteboard.stringValue = saved
        }
    }
    enum InjectorError: Error { case noAccessibility }
}

final class SystemPasteboard: PasteboardProvider {
    var stringValue: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let v = newValue { NSPasteboard.general.setString(v, forType: .string) }
        }
    }
}

final class CGEventPoster: EventPoster {
    func postCmdV() throws {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)!
        down.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)!
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

### Task 1.5: ModifierHotkeyMonitor — правый Command

**Files:**
- Create: `OpenVoice/Hotkey/ModifierHotkeyMonitor.swift`
- Test: `OpenVoiceTests/ModifierHotkeyMonitorTests.swift`

- [ ] Логика: модификатор зажат → ставим флаг и таймер 600мс. Если до отпускания пришёл другой `keyDown` или другой modifier — отменяем (значит пользователь набирал Cmd+чтото). Если отпустили чисто — триггер
- [ ] Дребезг 150мс между триггерами
- [ ] Тест: симулируем последовательность `flagsChanged` событий через инжектируемый источник

```swift
enum ModifierKey: String, CaseIterable {
    case rightCommand, rightOption, fn, leftControl
    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .fn: return 63
        case .leftControl: return 59
        }
    }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand, .leftControl: return .command   // см. реальный bitmask, fix-im
        case .rightOption: return .option
        case .fn: return .function
        }
    }
}

final class ModifierHotkeyMonitor {
    var onTrigger: (() -> Void)?
    private var key: ModifierKey
    private var armed = false
    private var lastTrigger = Date.distantPast
    private var globalMon: Any?
    private var localMon: Any?

    init(key: ModifierKey) { self.key = key }

    func start() {
        globalMon = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.handle($0) }
        localMon = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            self?.handle(e); return e
        }
    }

    func setKey(_ k: ModifierKey) { key = k; armed = false }

    private func handle(_ e: NSEvent) {
        if e.type == .keyDown { armed = false; return }
        let kc = e.keyCode
        let isOurKey = kc == key.keyCode
        if isOurKey {
            // any other modifier currently held? then disarm
            let otherFlags = e.modifierFlags.subtracting(key.flag).intersection([.command,.option,.control,.shift,.function])
            if e.modifierFlags.contains(key.flag) {
                armed = otherFlags.isEmpty
            } else if armed {
                armed = false
                let now = Date()
                if now.timeIntervalSince(lastTrigger) > 0.15 {
                    lastTrigger = now
                    onTrigger?()
                }
            }
        } else {
            armed = false
        }
    }
}
```

> **Важно:** распознавание именно правого Cmd vs левого делается через `event.modifierFlags.rawValue` и битмаск `NX_DEVICERCMDKEYMASK = 0x10` (левый: `0x08`). Реальная реализация должна использовать сырые флаги из CGEventGetFlags. Тест должен это покрывать.

### Task 1.6: RecordingCoordinator — стейт-машина

**Files:**
- Create: `OpenVoice/Coordinator/RecordingCoordinator.swift`
- Test: `OpenVoiceTests/RecordingCoordinatorTests.swift`

- [ ] Состояния: `idle / recording / transcribing / injecting / error(String)`
- [ ] Тест happy path: idle → toggle → recording → toggle → transcribing → injecting → idle
- [ ] Тест: ошибка транскрипции → `.error` → через 2 сек → idle
- [ ] Тест: повторный toggle во время `transcribing` игнорируется

```swift
@MainActor
final class RecordingCoordinator: ObservableObject {
    enum State: Equatable { case idle, recording, transcribing, injecting, error(String) }
    @Published private(set) var state: State = .idle

    private let recorder: AudioRecorder
    private let transcriber: Transcriber
    private let injector: TextInjector
    private let history: HistoryStore
    private let language: () -> String

    init(recorder: AudioRecorder, transcriber: Transcriber, injector: TextInjector, history: HistoryStore, language: @escaping () -> String) {
        self.recorder = recorder; self.transcriber = transcriber; self.injector = injector; self.history = history; self.language = language
    }

    func toggle() {
        switch state {
        case .idle: startRecording()
        case .recording: Task { await finishRecording() }
        default: break
        }
    }

    private func startRecording() {
        do {
            try recorder.start()
            state = .recording
        } catch {
            state = .error("Микрофон: \(error.localizedDescription)")
            scheduleReset()
        }
    }

    private func finishRecording() async {
        let pcm = recorder.stop()
        state = .transcribing
        do {
            let text = try await transcriber.transcribe(pcm: pcm, language: language())
            guard !text.isEmpty else { state = .error("Пусто"); scheduleReset(); return }
            history.save(text: text, durationSec: Double(pcm.count) / 4 / 16000, language: language())
            state = .injecting
            try await injector.inject(text)
            state = .idle
        } catch {
            state = .error("\(error.localizedDescription)")
            scheduleReset()
        }
    }

    private func scheduleReset() {
        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); state = .idle }
    }
}
```

---

## Phase 2: Хранение и модели

### Task 2.1: HistoryStore (SwiftData)

**Files:**
- Create: `OpenVoice/Model/Transcription.swift`, `OpenVoice/Model/HistoryStore.swift`
- Test: `OpenVoiceTests/HistoryStoreTests.swift` (in-memory `ModelContainer`)

- [ ] `@Model class Transcription { id, text, durationSec, createdAt, language }`
- [ ] Тесты: save → recent(limit:) → возвращает в порядке убывания даты; delete; clear
- [ ] Коммит

### Task 2.2: ModelManager — скачивание whisper-модели

**Files:**
- Create: `OpenVoice/Model/ModelManager.swift`
- Test: `OpenVoiceTests/ModelManagerTests.swift` (мок URLProtocol)

- [ ] `func ensureModel(name: String) async throws -> URL` — если файла нет, скачивает с `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<name>.bin`
- [ ] `progress: AsyncStream<Double>` через `URLSessionDelegate`
- [ ] Тест: первый запуск качает в `Application Support/OpenVoice/models/`, второй — возвращает существующий путь
- [ ] Тест: проверка SHA256 (для small захардкожена)
- [ ] Коммит

### Task 2.3: SettingsStore

**Files:**
- Create: `OpenVoice/Settings/SettingsStore.swift`

- [ ] Class `SettingsStore: ObservableObject` с `@AppStorage` для: `hotkeyKey: String` (raw), `language: String`, `modelName: String`, `restorePasteboard: Bool`
- [ ] Простые тесты на чтение/запись через `UserDefaults(suiteName: "test")`
- [ ] Коммит

---

## Phase 3: UI

### Task 3.1: AppCoordinator + AppDelegate

**Files:**
- Create: `OpenVoice/App/OpenVoiceApp.swift`, `OpenVoice/App/AppCoordinator.swift`

- [ ] `@main struct OpenVoiceApp: App { @NSApplicationDelegateAdaptor(AppDelegate.self) ... }`
- [ ] `AppCoordinator` собирает все зависимости, создаёт `RecordingCoordinator`, запускает `ModifierHotkeyMonitor`
- [ ] `AppDelegate.applicationDidFinishLaunching`: если модель не скачана — открыть OnboardingWindow, иначе — установить статус-айтем
- [ ] Запустить, убедиться что приложение живёт без окон, иконка в menu bar

### Task 3.2: MenuBarView (NSStatusItem + popover)

**Files:**
- Create: `OpenVoice/UI/MenuBar/MenuBarView.swift`, `MenuBarController.swift`

- [ ] `NSStatusItem` с SF Symbol `mic.fill` (меняется на `mic.circle.fill` при recording)
- [ ] Popover показывает: текущий статус, последние 3 транскрипции, кнопки «История», «Настройки», «Выход»
- [ ] При клике на запись истории — копировать в pasteboard

### Task 3.3: RecordingHUD (плавающее окно)

**Files:**
- Create: `OpenVoice/UI/HUD/RecordingHUD.swift`, `HUDPanel.swift`

- [ ] `NSPanel` с `.nonactivatingPanel`, `.hudWindow`, level `.statusBar`, `collectionBehavior` включая `.canJoinAllSpaces`
- [ ] SwiftUI содержимое: волна (`Canvas` + `levelPublisher`), таймер mm:ss, состояние
- [ ] Позиция: bottom-center главного экрана
- [ ] Появляется на `.recording`, `.transcribing`, `.injecting`, `.error`; исчезает на `.idle` через 200мс fade

### Task 3.4: HistoryWindow

**Files:**
- Create: `OpenVoice/UI/History/HistoryWindow.swift`, `HistoryView.swift`

- [ ] SwiftUI List с поиском (`.searchable`)
- [ ] Каждая ячейка: дата, длительность, текст с truncate, кнопка «Копировать», свайп «Удалить»
- [ ] Кнопка «Очистить всё» с confirmation

### Task 3.5: SettingsWindow

**Files:**
- Create: `OpenVoice/UI/Settings/SettingsWindow.swift`, `SettingsView.swift`

- [ ] Form с: Picker для хоткея, Picker для языка (ru/en/auto), Picker для модели (small/medium — с кнопкой «Скачать»), Picker микрофона, Toggle pasteboard
- [ ] Изменение хоткея → `ModifierHotkeyMonitor.setKey(...)`
- [ ] Изменение модели → ModelManager.ensureModel + Transcriber.load

### Task 3.6: OnboardingWindow

**Files:**
- Create: `OpenVoice/UI/Onboarding/OnboardingWindow.swift`, `OnboardingView.swift`

- [ ] Шаги через `TabView(selection:)`: Welcome → Microphone → Accessibility → Model download → Done
- [ ] Каждый шаг проверяет статус и кнопку «Дальше» делает активной только когда условие выполнено
- [ ] Microphone: `AVCaptureDevice.requestAccess(for: .audio)`
- [ ] Accessibility: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` + кнопка «Открыть Системные настройки»
- [ ] Model: показывает прогресс, кнопка «Скачать»

---

## Phase 4: Интеграция и полировка

### Task 4.1: End-to-end smoke

- [ ] Запустить приложение, пройти onboarding
- [ ] Открыть `TextEdit`, нажать правый Command, сказать «привет мир», нажать ещё раз
- [ ] Проверить, что текст вставился, появился в истории
- [ ] Если что-то не работает — отладить, не двигаться дальше

### Task 4.2: README

- [ ] Описание, скриншот, требования (macOS 14+), как собрать, как пользоваться, известные ограничения

---

## Self-Review

- ✅ Все требования спеки покрыты задачами (audio, transcription, injection, hotkey, history, onboarding, settings)
- ✅ Стейт-машина имеет тест на каждый переход
- ✅ Все «магические» значения из спеки (16kHz, 150мс дребезг, 500мс восстановление pasteboard) явно прописаны в коде
- ✅ Phases изолированы: Phase 1 даёт работающие модули с тестами, Phase 3 даёт UI поверх готового coordinator, Phase 4 — интеграция

---

## Выполнение

Подход: **inline execution** в этой сессии с короткими чекпоинтами после каждой Phase. После каждой фазы агент останавливается, отчитывается, ждёт «дальше» от пользователя. Это даёт возможность поправить курс рано.
