import AppKit
import Combine
import Foundation

/// Корневой объект, собирающий все зависимости и связывающий хоткей с
/// `RecordingCoordinator`. Один на всё приложение.
@MainActor
final class AppCoordinator: ObservableObject {
    let settings: SettingsStore
    let history: HistoryStore
    let recording: RecordingCoordinator
    let models: ModelManager
    let dictionary: CustomDictionary

    let recorder: AudioRecorder
    let injector: TextInjector
    let hotkeyMonitor: ModifierHotkeyMonitor

    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = SettingsStore()
        let history = HistoryStore()
        let models = ModelManager()
        let dictionary = CustomDictionary()
        let recorder = AudioRecorder()
        let injector = TextInjector(
            pasteboard: SystemPasteboard(),
            poster: CGEventKeystrokePoster(),
            trustChecker: { TextInjector.hasAccessibilityPermission() }
        )
        let recording = RecordingCoordinator(
            recorder: recorder,
            transcriber: StubTranscriber(),
            injector: injector,
            history: history,
            settings: settings,
            dictionary: dictionary
        )
        let hotkey = ModifierHotkeyMonitor(key: settings.hotkeyKey)

        self.settings = settings
        self.history = history
        self.recording = recording
        self.models = models
        self.dictionary = dictionary
        self.recorder = recorder
        self.injector = injector
        self.hotkeyMonitor = hotkey

        hotkey.onTrigger = { [weak recording] in
            Task { @MainActor in recording?.toggle() }
        }
    }

    @Published var accessibilityGranted: Bool = TextInjector.hasAccessibilityPermission()
    private var permissionTimer: Timer?

    func start() {
        Task {
            _ = await recorder.requestPermission()
            await MainActor.run {
                hotkeyMonitor.start()
                AppLog.app.info("App started, hotkey=\(self.settings.hotkeyKey.rawValue, privacy: .public), AX=\(self.accessibilityGranted, privacy: .public)")
                self.startPermissionWatcher()
            }
            await loadCurrentModelIfAvailable()
        }
    }

    /// Раз в секунду проверяем статус Accessibility — как только выдан,
    /// перезапускаем монитор хоткея (потому что `NSEvent.addGlobalMonitor`
    /// без Accessibility не получает события клавиш).
    private func startPermissionWatcher() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = TextInjector.hasAccessibilityPermission()
                if now != self.accessibilityGranted {
                    self.accessibilityGranted = now
                    AppLog.app.info("Accessibility changed: \(now, privacy: .public)")
                    if now {
                        self.hotkeyMonitor.start()
                    }
                }
            }
        }
    }

    func updateHotkey(_ key: ModifierKey) {
        settings.hotkeyKey = key
        hotkeyMonitor.setKey(key)
    }

    /// Если выбранная модель уже скачана — поднимает `WhisperTranscriber` и
    /// заменяет stub. Иначе оставляет stub и пишет лог.
    func loadCurrentModelIfAvailable() async {
        guard let modelName = ModelManager.ModelName(rawValue: settings.modelName) else {
            AppLog.app.error("Unknown model name: \(self.settings.modelName, privacy: .public)")
            return
        }
        guard models.isDownloaded(modelName) else {
            AppLog.app.info("Model \(modelName.rawValue, privacy: .public) is not downloaded yet — using stub")
            return
        }
        await loadModel(modelName)
    }

    /// Скачивает (если нужно) и загружает модель в активный транскрайбер.
    func loadModel(_ modelName: ModelManager.ModelName) async {
        do {
            let url = try await models.ensureModel(modelName)
            try await activateWhisper(modelURL: url)
            settings.modelName = modelName.rawValue
        } catch {
            AppLog.app.error("Model load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func activateWhisper(modelURL: URL) async throws {
#if canImport(whisper)
        let trans = WhisperTranscriber()
        try await trans.load(modelPath: modelURL)
        recording.setTranscriber(trans)
        AppLog.app.info("WhisperTranscriber activated")
#else
        AppLog.app.error("whisper module not linked — keeping stub. Add whisper.cpp via SPM.")
        _ = modelURL
#endif
    }
}
