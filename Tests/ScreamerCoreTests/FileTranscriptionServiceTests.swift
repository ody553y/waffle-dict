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
        #expect(capturedRequest.diarize == false)
        #expect(capturedRequest.jobID.isEmpty == false)

        #expect(result.text == "hello from file")
        #expect(result.backendID == "stub-whisper")
        #expect(result.durationSeconds == nil)
        #expect(result.segments == nil)
    }

    @Test func transcribeMapsWorkerSegmentsToResultSegments() async throws {
        let workerClient = MockWorkerFileTranscribingClient()
        workerClient.response = FileTranscriptionResponsePayload(
            jobID: "job-1",
            backendID: "stub-whisper",
            text: "hello from file",
            speakerEmbeddings: [
                "SPEAKER_00": [0.1, 0.2, 0.3],
                "SPEAKER_01": nil,
            ],
            segments: [
                .init(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00"),
                .init(start: 1.0, end: 2.0, text: "from file", speaker: "SPEAKER_01"),
            ]
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

        #expect(
            result.segments
            == [
                TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00"),
                TranscriptSegment(start: 1.0, end: 2.0, text: "from file", speaker: "SPEAKER_01"),
            ]
        )
        #expect(result.speakerEmbeddings == ["SPEAKER_00": [0.1, 0.2, 0.3]])
    }

    @Test func transcribePropagatesRequestDiarizationFlag() async throws {
        let workerClient = MockWorkerFileTranscribingClient()
        let service = FileTranscriptionService(workerClient: workerClient)

        let tempFile = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try Data("not-audio".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        _ = try await service.transcribe(
            fileURL: tempFile,
            modelID: "whisper-small",
            languageHint: "en",
            requestDiarization: true
        )

        let capturedRequest = try #require(workerClient.lastRequest)
        #expect(capturedRequest.diarize == true)
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
