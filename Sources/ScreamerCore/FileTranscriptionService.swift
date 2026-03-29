import AVFoundation
import Foundation

public protocol WorkerFileTranscribing: Sendable {
    func transcribeFile(
        _ requestPayload: FileTranscriptionRequestPayload
    ) async throws -> FileTranscriptionResponsePayload
}

extension WorkerClient: WorkerFileTranscribing {}

public struct FileTranscriptionResult: Equatable, Sendable {
    public let text: String
    public let durationSeconds: Double?
    public let backendID: String

    public init(text: String, durationSeconds: Double?, backendID: String) {
        self.text = text
        self.durationSeconds = durationSeconds
        self.backendID = backendID
    }
}

public final class FileTranscriptionService: @unchecked Sendable {
    private let workerClient: any WorkerFileTranscribing

    public init(workerClient: any WorkerFileTranscribing = WorkerClient()) {
        self.workerClient = workerClient
    }

    public func transcribe(
        fileURL: URL,
        modelID: String,
        languageHint: String?
    ) async throws -> FileTranscriptionResult {
        let response = try await workerClient.transcribeFile(
            FileTranscriptionRequestPayload(
                jobID: UUID().uuidString,
                modelID: modelID,
                filePath: fileURL.path,
                languageHint: languageHint,
                translateToEnglish: false
            )
        )

        return FileTranscriptionResult(
            text: response.text,
            durationSeconds: audioDurationSeconds(for: fileURL),
            backendID: response.backendID
        )
    }
}

private extension FileTranscriptionService {
    func audioDurationSeconds(for fileURL: URL) -> Double? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
            return nil
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else {
            return nil
        }

        let seconds = Double(audioFile.length) / sampleRate
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }

        return seconds
    }
}
