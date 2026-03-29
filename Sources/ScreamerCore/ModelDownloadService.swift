import CryptoKit
import Foundation

public enum ModelDownloadError: Error, Equatable {
    case checksumMismatch
    case cancelled
    case downloadAlreadyInProgress
}

public protocol ModelDownloadTransport: AnyObject, Sendable {
    func startDownload(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    func resumeDownload(
        from resumeData: Data,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    func cancelCurrentDownload(
        producingResumeData completion: @escaping @Sendable (Data?) -> Void
    )
}

public final class ModelDownloadService: @unchecked Sendable {
    private let catalogService: ModelCatalogService
    private let transport: any ModelDownloadTransport
    private let fileManager: FileManager
    private let lock = NSLock()
    private var activeDownloadID: String?

    public init(
        catalogService: ModelCatalogService = ModelCatalogService(),
        transport: (any ModelDownloadTransport)? = nil,
        fileManager: FileManager = .default
    ) {
        self.catalogService = catalogService
        self.transport = transport ?? URLSessionDownloadTransport()
        self.fileManager = fileManager
    }

    public func download(
        entry: ModelCatalogEntry,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try beginDownload(id: entry.id)
        defer { finishDownload() }

        let localURL = try await transport.startDownload(from: entry.downloadURL, progress: progress)
        try finalizeDownload(localURL: localURL, entry: entry)
    }

    public func resume(
        entry: ModelCatalogEntry,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try beginDownload(id: entry.id)
        defer { finishDownload() }

        let localURL: URL
        let resumeURL = resumeDataURL(for: entry.id)
        if fileManager.fileExists(atPath: resumeURL.path) {
            let resumeData = try Data(contentsOf: resumeURL)
            localURL = try await transport.resumeDownload(from: resumeData, progress: progress)
        } else {
            localURL = try await transport.startDownload(from: entry.downloadURL, progress: progress)
        }
        try finalizeDownload(localURL: localURL, entry: entry)
    }

    public func cancel(id: String) async {
        guard activeDownloadMatches(id) else { return }

        await withCheckedContinuation { continuation in
            transport.cancelCurrentDownload { [weak self] resumeData in
                if let resumeData {
                    try? self?.persistResumeData(resumeData, for: id)
                }
                continuation.resume()
            }
        }
    }

    public func verifyChecksum(of fileURL: URL, expectedChecksum: String) throws {
        let checksum = try checksum(for: fileURL)
        guard checksum.caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
            throw ModelDownloadError.checksumMismatch
        }
    }

    public func resumeDataURL(for id: String) -> URL {
        catalogService.downloadsDirectoryURL().appending(path: "\(id).resumedata")
    }

    private func finalizeDownload(localURL: URL, entry: ModelCatalogEntry) throws {
        defer {
            try? fileManager.removeItem(at: localURL)
        }

        try verifyChecksum(of: localURL, expectedChecksum: entry.sha256Checksum)

        let installDirectory = catalogService.installPath(for: entry.id)
        let installedFileURL = installDirectory.appending(path: localURL.lastPathComponent)

        if fileManager.fileExists(atPath: installDirectory.path) {
            try fileManager.removeItem(at: installDirectory)
        }
        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try fileManager.moveItem(at: localURL, to: installedFileURL)

        let resumeURL = resumeDataURL(for: entry.id)
        if fileManager.fileExists(atPath: resumeURL.path) {
            try fileManager.removeItem(at: resumeURL)
        }
    }

    private func checksum(for fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let chunkSize = 1_048_576

        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func beginDownload(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard activeDownloadID == nil else {
            throw ModelDownloadError.downloadAlreadyInProgress
        }
        activeDownloadID = id
    }

    private func finishDownload() {
        lock.lock()
        activeDownloadID = nil
        lock.unlock()
    }

    private func persistResumeData(_ resumeData: Data, for id: String) throws {
        let destination = resumeDataURL(for: id)
        try resumeData.write(to: destination, options: .atomic)
    }
}

private final class URLSessionDownloadTransport: NSObject, URLSessionDownloadDelegate, ModelDownloadTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession!
    private var currentTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: ((Double) -> Void)?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "\(Bundle.main.bundleIdentifier ?? "com.screamer.app").model-downloads"
        )
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func startDownload(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await start(taskFactory: { session.downloadTask(with: url) }, progress: progress)
    }

    func resumeDownload(
        from resumeData: Data,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await start(taskFactory: { session.downloadTask(withResumeData: resumeData) }, progress: progress)
    }

    func cancelCurrentDownload(
        producingResumeData completion: @escaping @Sendable (Data?) -> Void
    ) {
        lock.lock()
        let task = currentTask
        lock.unlock()

        task?.cancel(byProducingResumeData: completion)
    }

    private func start(
        taskFactory: () -> URLSessionDownloadTask,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            self.progressHandler = progress
            let task = taskFactory()
            currentTask = task
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        lock.lock()
        let handler = progressHandler
        lock.unlock()
        handler?(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        currentTask = nil
        progressHandler = nil
        lock.unlock()
        continuation?.resume(returning: location)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }

        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        currentTask = nil
        progressHandler = nil
        lock.unlock()

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            continuation?.resume(throwing: ModelDownloadError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
    }
}

private extension ModelDownloadService {
    func activeDownloadMatches(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeDownloadID == id
    }
}
