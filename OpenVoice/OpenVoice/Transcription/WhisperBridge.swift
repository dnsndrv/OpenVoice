#if canImport(whisper)
import Foundation
import whisper

/// Тонкая обёртка над whisper.cpp C API. Не thread-safe — должен
/// использоваться через `WhisperTranscriber` (actor).
final class WhisperBridge {
    enum BridgeError: Error, LocalizedError {
        case modelLoadFailed(String)
        case transcribeFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let p): return "Не удалось загрузить модель: \(p)"
            case .transcribeFailed(let c): return "whisper_full вернул \(c)"
            }
        }
    }

    private let context: OpaquePointer
    let modelPath: URL

    init(modelPath: URL) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath.path, params) else {
            throw BridgeError.modelLoadFailed(modelPath.path)
        }
        self.context = ctx
        self.modelPath = modelPath
        AppLog.transcribe.info("whisper context loaded from \(modelPath.lastPathComponent, privacy: .public)")
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(samples: [Float], language: String) throws -> String {
        let threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.suppress_blank = true
        params.n_threads = Int32(threads)

        return try language.withCString { langPtr -> String in
            params.language = langPtr
            params.detect_language = (language == "auto")

            let result = samples.withUnsafeBufferPointer { buf -> Int32 in
                whisper_full(context, params, buf.baseAddress, Int32(buf.count))
            }
            guard result == 0 else { throw BridgeError.transcribeFailed(result) }

            let n = whisper_full_n_segments(context)
            var output = ""
            for i in 0..<n {
                if let cstr = whisper_full_get_segment_text(context, i) {
                    output += String(cString: cstr)
                }
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// Реализация `Transcribing` поверх whisper.cpp.
actor WhisperTranscriber: Transcribing {
    private var bridge: WhisperBridge?
    private var loadedPath: URL?

    func load(modelPath: URL) throws {
        if loadedPath == modelPath, bridge != nil { return }
        bridge = try WhisperBridge(modelPath: modelPath)
        loadedPath = modelPath
    }

    func unload() {
        bridge = nil
        loadedPath = nil
    }

    func transcribe(pcm: Data, language: String) async throws -> String {
        guard let bridge else {
            throw WhisperBridge.BridgeError.modelLoadFailed("not loaded")
        }
        let samples: [Float] = pcm.withUnsafeBytes { raw -> [Float] in
            let buf = raw.bindMemory(to: Float.self)
            return Array(buf)
        }
        return try bridge.transcribe(samples: samples, language: language)
    }
}
#endif
