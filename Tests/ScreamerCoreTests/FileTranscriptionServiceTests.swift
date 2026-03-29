import Foundation
import Testing
@testable import ScreamerCore

struct FileTranscriptionServiceTests {
    @Test func transcribeBuildsWorkerRequestAndReturnsResult() async throws {
        let workerClient = MockWorkerFileTranscribingClient()
        workerClient.response = FileTranscriptionResponsePayload(
            jobID: "job-1",
            backendID: "stub-whisper",
            text: "hello from file"
        )

        let service = FileTranscriptionService(workerClient: workerClient)

        let tempFile = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try Data("not-audio".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let result = try await service.transcribe(
            fileURL: tempFile,
            modelID: "whisper-small",
            languageHint: "en"
        )

        let capturedRequest = try #require(workerClient.lastRequest)
        #expect(capturedRequest.modelID == "whisper-small")
        #expect(capturedRequest.filePath == tempFile.path)
        #expect(capturedRequest.languageHint == "en")
        #expect(capturedRequest.translateToEnglish == false)
        #expect(capturedRequest.jobID.isEmpty == false)

        #expect(result.text == "hello from file")
        #expect(result.backendID == "stub-whisper")
        #expect(result.durationSeconds == nil)
    }
}

private final class MockWorkerFileTranscribingClient: WorkerFileTranscribing, @unchecked Sendable {
    var response = FileTranscriptionResponsePayload(jobID: "job", backendID: "backend", text: "text")
    private(set) var lastRequest: FileTranscriptionRequestPayload?

    func transcribeFile(
        _ requestPayload: FileTranscriptionRequestPayload
    ) async throws -> FileTranscriptionResponsePayload {
        lastRequest = requestPayload
        return response
    }
}
