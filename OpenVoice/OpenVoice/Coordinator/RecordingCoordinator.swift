import Combine
import Foundation

@MainActor
final class RecordingCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case injecting
        case error(String)

        var isBusy: Bool {
            switch self {
            case .idle, .error: return false
            case .recording, .transcribing, .injecting: return true
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastText: String?

    private let recorder: AudioRecorder
    private var transcriber: Transcribing
    private let injector: TextInjector
    private let history: HistoryStore
    private let settings: SettingsStore

    init(recorder: AudioRecorder,
         transcriber: Transcribing,
         injector: TextInjector,
         history: HistoryStore,
         settings: SettingsStore) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.injector = injector
        self.history = history
        self.settings = settings
    }

    /// Подменяет реализацию транскрипции (например, при смене модели).
    func setTranscriber(_ new: Transcribing) {
        self.transcriber = new
    }

    func toggle() {
        switch state {
        case .idle: startRecording()
        case .recording: Task { await finishRecording() }
        case .transcribing, .injecting, .error:
            AppLog.coord.debug("toggle ignored in state \(String(describing: self.state))")
        }
    }

    private func startRecording() {
        do {
            try recorder.start()
            state = .recording
        } catch {
            AppLog.coord.error("start failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            scheduleReset()
        }
    }

    private func finishRecording() async {
        let pcm = recorder.stop()
        let durationSec = Double(pcm.count) / 4.0 / 16_000.0
        AppLog.coord.info("recording stopped: \(pcm.count, privacy: .public) bytes, \(durationSec, privacy: .public)s")
        guard durationSec > 0.1 else {
            let detail = String(format: "%dБ ~%.0fмс", pcm.count, durationSec * 1000)
            state = .error(pcm.isEmpty ? "Микрофон молчит (\(detail))" : "Слишком коротко (\(detail))")
            scheduleReset()
            return
        }

        state = .transcribing
        do {
            let text = try await transcriber.transcribe(pcm: pcm, language: settings.language)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                state = .error("Пусто")
                scheduleReset()
                return
            }
            lastText = trimmed
            history.save(text: trimmed, durationSec: durationSec, language: settings.language)

            state = .injecting
            do {
                try await injector.inject(trimmed, restorePasteboard: settings.restorePasteboard)
                state = .idle
            } catch TextInjector.InjectorError.noAccessibility {
                state = .error("Нет Accessibility — текст в pasteboard")
                scheduleReset()
            } catch {
                state = .error(error.localizedDescription)
                scheduleReset()
            }
        } catch {
            AppLog.coord.error("transcribe failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            scheduleReset()
        }
    }

    private func scheduleReset() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if case .error = self?.state { self?.state = .idle }
            }
        }
    }
}
