import AVFoundation
import Combine
import Foundation

/// Захватывает звук с системного микрофона и пишет 16 kHz mono float32 PCM.
///
/// Формат подобран под whisper.cpp: ему нужны именно `[Float]` сэмплы 16 kHz.
/// `levelPublisher` шлёт RMS уровня в [0..1] для индикатора.
final class AudioRecorder {
    enum Error: Swift.Error, LocalizedError {
        case engineFailed(Swift.Error)
        case converterUnavailable
        case noPermission

        var errorDescription: String? {
            switch self {
            case .engineFailed(let e): return "Аудио: \(e.localizedDescription)"
            case .converterUnavailable: return "Не удалось создать конвертер аудио"
            case .noPermission: return "Нет доступа к микрофону"
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

    /// Длительность записанного буфера в секундах.
    var recordedSeconds: Double {
        bufferQueue.sync { Double(pcmBuffer.count) / 4.0 / 16_000.0 }
    }

    func requestPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
        return await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in cont.resume(returning: granted) }
        }
    }

    func start() throws {
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        guard granted else { throw Error.noPermission }

        bufferQueue.sync { pcmBuffer.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw Error.converterUnavailable
        }
        self.converter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
            AppLog.audio.debug("AudioRecorder started, inputFormat=\(inputFormat)")
        } catch {
            input.removeTap(onBus: 0)
            throw Error.engineFailed(error)
        }
    }

    /// Останавливает запись и возвращает сырые float32 PCM сэмплы.
    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return bufferQueue.sync { pcmBuffer }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
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
            return buffer
        }

        if let convError {
            AppLog.audio.error("Convert error: \(convError.localizedDescription)")
            return
        }
        guard status != .error, output.frameLength > 0, let ptr = output.floatChannelData?[0] else { return }

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
