import Foundation

/// Менеджер скачивания whisper-моделей с HuggingFace.
@MainActor
final class ModelManager: ObservableObject {
    enum ModelName: String, CaseIterable, Identifiable {
        case tiny, base, small, medium, large_v3 = "large-v3"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .tiny: return "tiny (~75 MB)"
            case .base: return "base (~140 MB)"
            case .small: return "small (~460 MB)"
            case .medium: return "medium (~1.4 GB)"
            case .large_v3: return "large-v3 (~2.9 GB)"
            }
        }
        var ggmlFileName: String { "ggml-\(rawValue).bin" }
        var url: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(ggmlFileName)")!
        }
    }

    enum LoadState: Equatable {
        case absent
        case downloading(Double)
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .absent
    /// Имя модели, которая сейчас скачивается (для показа в UI).
    @Published private(set) var activeDownload: ModelName?
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var sessionDelegate: DownloadDelegate?

    static var modelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenVoice", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    func localURL(for model: ModelName) -> URL {
        Self.modelsDirectory.appendingPathComponent(model.ggmlFileName)
    }

    func isDownloaded(_ model: ModelName) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    /// Возвращает локальный путь к модели; если её нет — скачивает.
    func ensureModel(_ model: ModelName) async throws -> URL {
        let target = localURL(for: model)
        if FileManager.default.fileExists(atPath: target.path) {
            state = .ready(target)
            return target
        }
        return try await download(model: model, to: target)
    }

    /// Только скачивание (если файл уже есть — удаляется и качается заново).
    func download(model: ModelName, to target: URL) async throws -> URL {
        try? FileManager.default.removeItem(at: target)
        state = .downloading(0)
        activeDownload = model

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let delegate = DownloadDelegate(
                target: target,
                onProgress: { [weak self] p in
                    Task { @MainActor in self?.state = .downloading(p) }
                },
                onFinish: { [weak self] result in
                    Task { @MainActor in
                        switch result {
                        case .success(let url):
                            self?.state = .ready(url)
                            self?.activeDownload = nil
                            cont.resume(returning: url)
                        case .failure(let err):
                            self?.state = .failed(err.localizedDescription)
                            self?.activeDownload = nil
                            cont.resume(throwing: err)
                        }
                    }
                }
            )
            self.sessionDelegate = delegate
            let session = URLSession(configuration: .default,
                                     delegate: delegate,
                                     delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: model.url)
            self.downloadTask = task
            task.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        activeDownload = nil
        state = .absent
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let target: URL
    let onProgress: (Double) -> Void
    let onFinish: (Result<URL, Error>) -> Void

    init(target: URL,
         onProgress: @escaping (Double) -> Void,
         onFinish: @escaping (Result<URL, Error>) -> Void) {
        self.target = target
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(min(1, max(0, p)))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: location, to: target)
            onFinish(.success(target))
        } catch {
            onFinish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            onFinish(.failure(error))
        }
    }
}
