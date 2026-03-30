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
    public let segments: [TranscriptSegment]?
    public let speakerEmbeddings: [String: [Float]]?

    public init(
        text: String,
        durationSeconds: Double?,
        backendID: String,
        segments: [TranscriptSegment]? = nil,
        speakerEmbeddings: [String: [Float]]? = nil
    ) {
        self.text = text
        self.durationSeconds = durationSeconds
        self.backendID = backendID
        self.segments = segments
        self.speakerEmbeddings = speakerEmbeddings
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
        languageHint: String?,
        requestDiarization: Bool = false
    ) async throws -> FileTranscriptionResult {
        try await PerformanceMetrics.shared.measureAsync("file.transcription.e2e") {
            let response = try await workerClient.transcribeFile(
                FileTranscriptionRequestPayload(
                    jobID: UUID().uuidString,
                    modelID: modelID,
                    filePath: fileURL.path,
                    languageHint: languageHint,
                    translateToEnglish: false,
                    diarize: requestDiarization
                )
            )

            return FileTranscriptionResult(
                text: response.text,
                durationSeconds: audioDurationSeconds(for: fileURL),
                backendID: response.backendID,
                segments: response.segments?.map {
                    TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker)
                },
                speakerEmbeddings: normalizedSpeakerEmbeddings(from: response.speakerEmbeddings)
            )
        }
    }
}

private extension FileTranscriptionService {
    func normalizedSpeakerEmbeddings(
        from embeddings: [String: [Float]?]?
    ) -> [String: [Float]]? {
        guard let embeddings else { return nil }

        var normalized: [String: [Float]] = [:]
        for (label, embedding) in embeddings {
            guard let embedding, embedding.isEmpty == false else { continue }
            normalized[label] = embedding
        }

        return normalized.isEmpty ? nil : normalized
    }

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
