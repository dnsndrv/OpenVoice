import Foundation

/// Абстракция для транскрипции PCM-данных в текст. Позволяет подменять
/// реализацию (whisper.cpp / стаб / mock в тестах).
protocol Transcribing: Sendable {
    func transcribe(pcm: Data, language: String) async throws -> String
}

/// Заглушка, которую используем пока не подключён whisper.cpp.
/// Возвращает фиктивную фразу с длительностью, чтобы можно было проверить
/// весь end-to-end путь (запись → вставка) без реальной модели.
struct StubTranscriber: Transcribing {
    func transcribe(pcm: Data, language: String) async throws -> String {
        try await Task.sleep(nanoseconds: 200_000_000)
        let seconds = Double(pcm.count) / 4.0 / 16_000.0
        return String(format: "[заглушка %.1fс, lang=%@]", seconds, language)
    }
}
