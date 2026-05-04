import AVFoundation
import Combine
import Foundation

/// Захватывает звук с системного микрофона и пишет 16 kHz mono float32 PCM —
/// формат, который ожидает whisper.cpp.
///
/// Tap ставится в нативном формате микрофона (обычно 48 kHz / mono), а
/// затем мы конвертируем буфер в 16 kHz через `AVAudioConverter` — это
/// единственная стабильная схема на macOS 15.
final class AudioRecorder {
    enum Error: Swift.Error, LocalizedError {
        case engineFailed(Swift.Error)
        case noPermission
        case noInputDevice
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .engineFailed(let e): return "Аудио: \(e.localizedDescription)"
            case .noPermission: return "Нет доступа к микрофону"
            case .noInputDevice: return "Нет устройства ввода"
            case .converterUnavailable: return "Не удалось создать конвертер"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let bufferQueue = DispatchQueue(label: "com.openvoice.audio.buffer")
    private var pcmBuffer = Data()
    private let levelSubject = PassthroughSubject<Float, Never>()
    private var converter: AVAudioConverter?

    /// Целевой формат для whisper.cpp.
    private let targetFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: 16_000,
                      channels: 1,
                      interleaved: false)!
    }()

    var levelPublisher: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    var recordedSeconds: Double {
        bufferQueue.sync { Double(pcmBuffer.count) / 4.0 / 16_000.0 }
    }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        guard granted else { throw Error.noPermission }

        bufferQueue.sync { pcmBuffer.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        AppLog.audio.info("inputFormat: sr=\(inputFormat.sampleRate, privacy: .public) ch=\(inputFormat.channelCount, privacy: .public)")

        guard inputFormat.sampleRate > 0 else { throw Error.noInputDevice }

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw Error.converterUnavailable
        }
        self.converter = conv

        input.removeTap(onBus: 0)
        // Tap в input-формате — это требование AVAudioEngine.
        // Конвертация в 16 kHz происходит в process().
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()

        do {
            try engine.start()
            AppLog.audio.info("AudioRecorder started")
        } catch {
            input.removeTap(onBus: 0)
            throw Error.engineFailed(error)
        }
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let snapshot = bufferQueue.sync { pcmBuffer }
        AppLog.audio.info("AudioRecorder stopped: \(snapshot.count, privacy: .public) bytes captured")
        return snapshot
    }

    private func process(buffer inputBuffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: output, error: &convError) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .endOfStream
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return inputBuffer
        }

        if let convError {
            AppLog.audio.error("convert error: \(convError.localizedDescription, privacy: .public)")
            return
        }
        guard status != .error,
              output.frameLength > 0,
              let ptr = output.floatChannelData?[0] else { return }

        let frameCount = Int(output.frameLength)
        let bytes = Data(bytes: ptr, count: frameCount * MemoryLayout<Float>.size)

        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let s = ptr[i]
            sumSquares += s * s
        }
        let rms = sqrtf(sumSquares / Float(max(frameCount, 1)))
        let level = min(1, rms * 4)

        bufferQueue.sync { pcmBuffer.append(bytes) }
        DispatchQueue.main.async { [weak self] in self?.levelSubject.send(level) }
    }
}
