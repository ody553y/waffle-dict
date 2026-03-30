import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct TranscriptActionServiceTests {
    @Test func summariseBuildsExpectedPromptAndTemperature() async throws {
        let client = MockLMStudioClient()
        client.completionResponse = ChatCompletionResponse(
            id: "chat-1",
            choices: [
                .init(
                    index: 0,
                    message: .init(role: "assistant", content: "Summary output"),
                    finishReason: "stop"
                ),
            ]
        )
        let service = TranscriptActionService(lmStudioClient: client)

        let result = try await service.perform(
            action: .summarise,
            on: makeTranscript(id: 42, text: "Line one.\nLine two."),
            modelID: "qwen3-8b"
        )
        let request = try #require(client.lastChatRequest)

        #expect(request.model == "qwen3-8b")
        #expect(request.temperature == 0.3)
        #expect(request.maxTokens == nil)
        #expect(request.stream == false)
        #expect(request.messages.count == 2)
        #expect(request.messages[0].role == "system")
        #expect(request.messages[0].content.contains("Summarise the following transcript concisely"))
        #expect(request.messages[1].content == "Transcript:\n\nLine one.\nLine two.")

        #expect(result.action == .summarise)
        #expect(result.sourceTranscriptID == 42)
        #expect(result.resultText == "Summary output")
        #expect(result.modelUsed == "qwen3-8b")
    }

    @Test func translateBuildsExpectedPromptAndInput() async throws {
        let client = MockLMStudioClient()
        let service = TranscriptActionService(lmStudioClient: client)

        _ = try await service.perform(
            action: .translate(targetLanguage: "Spanish"),
            on: makeTranscript(id: 43, text: "Hello world."),
            modelID: "qwen3-8b"
        )
        let request = try #require(client.lastChatRequest)

        #expect(request.temperature == 0.3)
        #expect(request.messages[0].content.contains("Translate the following transcript into Spanish"))
        #expect(request.messages[1].content == "Transcript:\n\nHello world.")
    }

    @Test func questionBuildsExpectedPromptAndQuestionFormatting() async throws {
        let client = MockLMStudioClient()
        let service = TranscriptActionService(lmStudioClient: client)

        _ = try await service.perform(
            action: .askQuestion(question: "Who owns the action item?"),
            on: makeTranscript(id: 44, text: "Alice owns action item 1."),
            modelID: "qwen3-8b"
        )
        let request = try #require(client.lastChatRequest)

        #expect(request.temperature == 0.7)
        #expect(request.messages[0].content.contains("Answer the user's question based only on the transcript provided"))
        #expect(
            request.messages[1].content
            == "Transcript:\n\nAlice owns action item 1.\n\nQuestion: Who owns the action item?"
        )
    }

    @Test func customPromptBuildsExpectedPromptAndFormatting() async throws {
        let client = MockLMStudioClient()
        let service = TranscriptActionService(lmStudioClient: client)

        _ = try await service.perform(
            action: .customPrompt(prompt: "Extract action items as bullets."),
            on: makeTranscript(id: 45, text: "Ship task A by Friday."),
            modelID: "qwen3-8b"
        )
        let request = try #require(client.lastChatRequest)

        #expect(request.temperature == 0.7)
        #expect(request.messages[0].content == "You are a helpful assistant working with a transcript.")
        #expect(
            request.messages[1].content
            == "Extract action items as bullets.\n\nTranscript:\n\nShip task A by Friday."
        )
    }

    @Test func longTranscriptPrependsSystemPromptNote() async throws {
        let client = MockLMStudioClient()
        let service = TranscriptActionService(lmStudioClient: client)
        let longText = String(repeating: "a", count: 12_001)

        _ = try await service.perform(
            action: .summarise,
            on: makeTranscript(id: 46, text: longText),
            modelID: "qwen3-8b"
        )
        let request = try #require(client.lastChatRequest)

        #expect(
            request.messages[0].content.hasPrefix("The transcript is long. Focus on the most important content.")
        )
    }

    @Test func performStreamingUsesStreamingRequestAndPassesThroughDeltas() async throws {
        let client = MockLMStudioClient()
        client.streamResponse = ["Part 1", " + Part 2"]
        let service = TranscriptActionService(lmStudioClient: client)

        let stream = service.performStreaming(
            action: .summarise,
            on: makeTranscript(id: 47, text: "Long transcript"),
            modelID: "qwen3-8b"
        )
        var received: [String] = []
        for try await chunk in stream {
            received.append(chunk)
        }

        let request = try #require(client.lastStreamRequest)
        #expect(request.stream == true)
        #expect(received == ["Part 1", " + Part 2"])
    }

    @Test func availableModelsPassesThroughToClient() async throws {
        let client = MockLMStudioClient()
        client.modelsResponse = [LMStudioModel(id: "model-a"), LMStudioModel(id: "model-b")]
        let service = TranscriptActionService(lmStudioClient: client)

        let models = try await service.availableModels()

        #expect(client.fetchModelsCallCount == 1)
        #expect(models.map(\.id) == ["model-a", "model-b"])
    }
}

private func makeTranscript(id: Int64, text: String) -> TranscriptRecord {
    TranscriptRecord(
        id: id,
        createdAt: Date(timeIntervalSince1970: 1_710_000_000),
        sourceType: "dictation",
        sourceFileName: nil,
        modelID: "whisper-small",
        languageHint: "en",
        durationSeconds: 5,
        text: text
    )
}

private final class MockLMStudioClient: LMStudioClientProtocol, @unchecked Sendable {
    var modelsResponse: [LMStudioModel] = []
    var completionResponse: ChatCompletionResponse = .init(
        id: "chat-default",
        choices: [
            .init(
                index: 0,
                message: .init(role: "assistant", content: "default response"),
                finishReason: "stop"
            ),
        ]
    )
    var streamResponse: [String] = []
    var fetchModelsCallCount = 0
    var lastChatRequest: ChatCompletionRequest?
    var lastStreamRequest: ChatCompletionRequest?

    func fetchModels() async throws -> [LMStudioModel] {
        fetchModelsCallCount += 1
        return modelsResponse
    }

    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        lastChatRequest = request
        return completionResponse
    }

    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<String, Error> {
        lastStreamRequest = request
        let chunks = streamResponse
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
