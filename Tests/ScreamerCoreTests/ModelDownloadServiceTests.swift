import Foundation
import Testing
@testable import ScreamerCore

struct ModelDownloadServiceTests {
    @Test func verifyChecksumMatchesFileContents() async throws {
        let tempDirectory = try makeDownloadTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogService = ModelCatalogService(
            manifestDataLoader: { Data("[]".utf8) },
            applicationSupportDirectory: tempDirectory
        )
        let service = ModelDownloadService(
            catalogService: catalogService,
            transport: MockDownloadTransport()
        )

        let fileURL = tempDirectory.appending(path: "download.bin")
        let fileData = Data("checksum-demo".utf8)
        try fileData.write(to: fileURL)

        try service.verifyChecksum(
            of: fileURL,
            expectedChecksum: "edf62a9f6e8d5d9b281591376498672904b904f8335c609ed5519681a7f5d94b"
        )
    }

    @Test func verifyChecksumThrowsForMismatch() async throws {
        let tempDirectory = try makeDownloadTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogService = ModelCatalogService(
            manifestDataLoader: { Data("[]".utf8) },
            applicationSupportDirectory: tempDirectory
        )
        let service = ModelDownloadService(
            catalogService: catalogService,
            transport: MockDownloadTransport()
        )

        let fileURL = tempDirectory.appending(path: "download.bin")
        try Data("checksum-demo".utf8).write(to: fileURL)

        #expect(throws: ModelDownloadError.checksumMismatch) {
            try service.verifyChecksum(of: fileURL, expectedChecksum: "wrong")
        }
    }

    @Test func resumeUsesStoredResumeDataAndInstallsDownload() async throws {
        let tempDirectory = try makeDownloadTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogService = ModelCatalogService(
            manifestDataLoader: { Data("[]".utf8) },
            applicationSupportDirectory: tempDirectory
        )

        let downloadedFile = tempDirectory.appending(path: "resume-download.bin")
        try Data("resumed".utf8).write(to: downloadedFile)

        let transport = MockDownloadTransport()
        transport.resumeResultURL = downloadedFile

        let service = ModelDownloadService(
            catalogService: catalogService,
            transport: transport
        )

        let entry = ModelCatalogEntry(
            id: "whisper-small",
            family: .whisper,
            displayName: "Whisper Small",
            sizeMB: 488,
            languages: ["en"],
            supportsLive: false,
            supportsTranslation: true,
            downloadURL: URL(string: "https://example.com/whisper-small.bin")!,
            sha256Checksum: "cf8ad4d9e25bd81545d80a8f1a72029890dc93ab3c7af55c5bc92ccfd525db03",
            available: true
        )

        try Data("resume-data".utf8).write(to: service.resumeDataURL(for: entry.id))

        try await service.resume(entry: entry) { _ in }

        #expect(transport.resumeInvocationCount == 1)
        #expect(catalogService.isInstalled(id: entry.id))
        #expect(FileManager.default.fileExists(atPath: service.resumeDataURL(for: entry.id).path) == false)
    }

    @Test func cancelPersistsResumeDataForActiveDownload() async throws {
        let tempDirectory = try makeDownloadTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let catalogService = ModelCatalogService(
            manifestDataLoader: { Data("[]".utf8) },
            applicationSupportDirectory: tempDirectory
        )
        let transport = MockDownloadTransport()
        transport.downloadDelayNanoseconds = 500_000_000
        transport.cancelResumeData = Data("resume-data".utf8)

        let service = ModelDownloadService(
            catalogService: catalogService,
            transport: transport
        )

        let pendingFile = tempDirectory.appending(path: "pending-download.bin")
        try Data("pending".utf8).write(to: pendingFile)
        transport.downloadResultURL = pendingFile

        let entry = ModelCatalogEntry(
            id: "whisper-base",
            family: .whisper,
            displayName: "Whisper Base",
            sizeMB: 142,
            languages: ["en"],
            supportsLive: false,
            supportsTranslation: true,
            downloadURL: URL(string: "https://example.com/whisper-base.bin")!,
            sha256Checksum: "ddf68c33a0151f53d258f4b80240dc0ec7884cf9c23ea8e28444dfeee1fe8c12",
            available: true
        )

        let downloadTask = Task {
            try await service.download(entry: entry) { _ in }
        }

        try await Task.sleep(for: .milliseconds(50))
        await service.cancel(id: entry.id)

        await #expect(throws: ModelDownloadError.cancelled) {
            try await downloadTask.value
        }

        let resumeData = try Data(contentsOf: service.resumeDataURL(for: entry.id))
        #expect(resumeData == Data("resume-data".utf8))
    }
}

private final class MockDownloadTransport: ModelDownloadTransport, @unchecked Sendable {
    var downloadResultURL: URL?
    var resumeResultURL: URL?
    var downloadDelayNanoseconds: UInt64 = 0
    var cancelResumeData: Data?
    private(set) var resumeInvocationCount = 0
    private var cancellationContinuation: CheckedContinuation<Void, Never>?

    func startDownload(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        progress(0.25)
        if downloadDelayNanoseconds > 0 {
            await withCheckedContinuation { continuation in
                cancellationContinuation = continuation
            }
            throw ModelDownloadError.cancelled
        }
        return try #require(downloadResultURL)
    }

    func resumeDownload(
        from resumeData: Data,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        resumeInvocationCount += 1
        progress(0.75)
        return try #require(resumeResultURL)
    }

    func cancelCurrentDownload(
        producingResumeData completion: @escaping @Sendable (Data?) -> Void
    ) {
        completion(cancelResumeData)
        cancellationContinuation?.resume()
        cancellationContinuation = nil
    }
}

private func makeDownloadTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
