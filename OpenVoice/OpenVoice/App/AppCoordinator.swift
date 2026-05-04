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

    let recorder: AudioRecorder
    let injector: TextInjector
    let hotkeyMonitor: ModifierHotkeyMonitor

    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = SettingsStore()
        let history = HistoryStore()
        let recorder = AudioRecorder()
        let injector = TextInjector(
            pasteboard: SystemPasteboard(),
            poster: CGEventKeystrokePoster(),
            trustChecker: { TextInjector.hasAccessibilityPermission() }
        )
        let transcriber: Transcribing = StubTranscriber()
        let recording = RecordingCoordinator(
            recorder: recorder,
            transcriber: transcriber,
            injector: injector,
            history: history,
            settings: settings
        )
        let hotkey = ModifierHotkeyMonitor(key: settings.hotkeyKey)

        self.settings = settings
        self.history = history
        self.recording = recording
        self.recorder = recorder
        self.injector = injector
        self.hotkeyMonitor = hotkey

        hotkey.onTrigger = { [weak recording] in
            Task { @MainActor in recording?.toggle() }
        }
    }

    func start() {
        Task {
            _ = await recorder.requestPermission()
            await MainActor.run {
                hotkeyMonitor.start()
                AppLog.app.info("App started, hotkey=\(self.settings.hotkeyKey.rawValue, privacy: .public)")
            }
        }
    }

    func updateHotkey(_ key: ModifierKey) {
        settings.hotkeyKey = key
        hotkeyMonitor.setKey(key)
    }
}
