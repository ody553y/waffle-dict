import Foundation

public enum TranscriptAction: Equatable, Sendable {
    case summarise
    case translate(targetLanguage: String)
    case askQuestion(question: String)
    case customPrompt(prompt: String)
}

public struct TranscriptActionResult: Equatable, Sendable {
    public let action: TranscriptAction
    public let sourceTranscriptID: Int64
    public let resultText: String
    public let modelUsed: String
    public let createdAt: Date

    public init(
        action: TranscriptAction,
        sourceTranscriptID: Int64,
        resultText: String,
        modelUsed: String,
        createdAt: Date
    ) {
        self.action = action
        self.sourceTranscriptID = sourceTranscriptID
        self.resultText = resultText
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }
}

public enum TranscriptActionServiceError: Error, Equatable {
    case transcriptMissingID
    case emptyResponse
}

public final class TranscriptActionService: Sendable {
    private let lmStudioClient: any LMStudioClientProtocol

    public init(lmStudioClient: any LMStudioClientProtocol) {
        self.lmStudioClient = lmStudioClient
    }

    public func perform(
        action: TranscriptAction,
        on transcript: TranscriptRecord,
        modelID: String
    ) async throws -> TranscriptActionResult {
        let sourceTranscriptID = try requireTranscriptID(from: transcript)
        let request = makeRequest(
            for: action,
            transcriptText: transcript.text,
            modelID: modelID,
            stream: false
        )
        let response = try await lmStudioClient.chatCompletion(request)

        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw TranscriptActionServiceError.emptyResponse
        }

        return TranscriptActionResult(
            action: action,
            sourceTranscriptID: sourceTranscriptID,
            resultText: content,
            modelUsed: modelID,
            createdAt: Date()
        )
    }

    public func performStreaming(
        action: TranscriptAction,
        on transcript: TranscriptRecord,
        modelID: String
    ) -> AsyncThrowingStream<String, Error> {
        let request = makeRequest(
            for: action,
            transcriptText: transcript.text,
            modelID: modelID,
            stream: true
        )
        return lmStudioClient.streamChatCompletion(request)
    }

    public func availableModels() async throws -> [LMStudioModel] {
        try await lmStudioClient.fetchModels()
    }
}

private extension TranscriptActionService {
    static let longTranscriptThreshold = 12_000
    static let longTranscriptNote = "The transcript is long. Focus on the most important content."
    static let summarisePrompt = "You are a helpful assistant. Summarise the following transcript concisely, preserving key points and any action items. Output only the summary, no preamble."
    static let questionPrompt = "You are a helpful assistant. Answer the user's question based only on the transcript provided. If the answer is not in the transcript, say so. Be concise."
    static let customPrompt = "You are a helpful assistant working with a transcript."

    func requireTranscriptID(from transcript: TranscriptRecord) throws -> Int64 {
        guard let sourceTranscriptID = transcript.id else {
            throw TranscriptActionServiceError.transcriptMissingID
        }
        return sourceTranscriptID
    }

    func makeRequest(
        for action: TranscriptAction,
        transcriptText: String,
        modelID: String,
        stream: Bool
    ) -> ChatCompletionRequest {
        let systemPrompt = buildSystemPrompt(for: action, transcriptText: transcriptText)
        let userPrompt = buildUserPrompt(for: action, transcriptText: transcriptText)

        return ChatCompletionRequest(
            model: modelID,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt),
            ],
            temperature: temperature(for: action),
            maxTokens: nil,
            stream: stream
        )
    }

    func buildSystemPrompt(for action: TranscriptAction, transcriptText: String) -> String {
        let basePrompt: String
        switch action {
        case .summarise:
            basePrompt = Self.summarisePrompt
        case .translate(let targetLanguage):
            basePrompt = "You are a professional translator. Translate the following transcript into \(targetLanguage). Preserve the meaning and tone. Output only the translation, no preamble."
        case .askQuestion:
            basePrompt = Self.questionPrompt
        case .customPrompt:
            basePrompt = Self.customPrompt
        }

        if transcriptText.count > Self.longTranscriptThreshold {
            return "\(Self.longTranscriptNote) \(basePrompt)"
        }
        return basePrompt
    }

    func buildUserPrompt(for action: TranscriptAction, transcriptText: String) -> String {
        switch action {
        case .summarise, .translate:
            return "Transcript:\n\n\(transcriptText)"
        case .askQuestion(let question):
            return "Transcript:\n\n\(transcriptText)\n\nQuestion: \(question)"
        case .customPrompt(let prompt):
            return "\(prompt)\n\nTranscript:\n\n\(transcriptText)"
        }
    }

    func temperature(for action: TranscriptAction) -> Double {
        switch action {
        case .summarise, .translate:
            return 0.3
        case .askQuestion, .customPrompt:
            return 0.7
        }
    }
}
