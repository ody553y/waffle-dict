import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct ExportPipelineRunnerTests {
    @Test func runChainsOutputsAndSavesEachStepResult() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try seedTranscript(text: "initial transcript", in: store)
        let transcriptID = try #require(transcript.id)

        let client = MockPipelineRunnerLMStudioClient()
        client.responses = ["step one output", "step two output", "step three output"]
        let actionService = TranscriptActionService(lmStudioClient: client)
        let runner = ExportPipelineRunner(actionService: actionService, transcriptStore: store)

        let finalText = try await runner.run(
            pipeline: makePipeline(
                steps: [
                    ("Template A", "Prompt A"),
                    ("Template B", "Prompt B"),
                    ("Template C", "Prompt C"),
                ]
            ),
            transcript: transcript,
            modelID: "qwen3-8b"
        )

        #expect(finalText == "step three output")

        let actions = try store.fetchActions(forTranscriptID: transcriptID)
        #expect(actions.count == 3)
        #expect(actions.allSatisfy { $0.actionType == "pipeline_step" })
        #expect(actions.map(\.actionInput) == ["Template C", "Template B", "Template A"])
        #expect(actions.map(\.resultText) == ["step three output", "step two output", "step one output"])
    }

    @Test func runUsesPreviousStepOutputAsNextStepInput() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try seedTranscript(text: "original text", in: store)

        let client = MockPipelineRunnerLMStudioClient()
        client.responses = ["first transformed", "second transformed"]
        let actionService = TranscriptActionService(lmStudioClient: client)
        let runner = ExportPipelineRunner(actionService: actionService, transcriptStore: store)

        _ = try await runner.run(
            pipeline: makePipeline(
                steps: [
                    ("Step 1", "Prompt 1"),
                    ("Step 2", "Prompt 2"),
                ]
            ),
            transcript: transcript,
            modelID: "qwen3-8b"
        )

        let requests = client.chatRequests
        #expect(requests.count == 2)
        #expect(requests[0].messages[1].content == "Prompt 1\n\nTranscript:\n\noriginal text")
        #expect(requests[1].messages[1].content == "Prompt 2\n\nTranscript:\n\nfirst transformed")
    }

    @Test func runThrowsEmptyPipelineErrorWhenNoSteps() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try seedTranscript(text: "text", in: store)

        let client = MockPipelineRunnerLMStudioClient()
        let actionService = TranscriptActionService(lmStudioClient: client)
        let runner = ExportPipelineRunner(actionService: actionService, transcriptStore: store)

        await #expect(throws: ExportPipelineError.emptyPipeline) {
            _ = try await runner.run(
                pipeline: makePipeline(steps: []),
                transcript: transcript,
                modelID: "qwen3-8b"
            )
        }
    }

    @Test func runPropagatesFirstStepFailure() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try seedTranscript(text: "text", in: store)

        let client = MockPipelineRunnerLMStudioClient()
        client.errorAtCallIndex = 0
        let actionService = TranscriptActionService(lmStudioClient: client)
        let runner = ExportPipelineRunner(actionService: actionService, transcriptStore: store)

        await #expect(throws: MockPipelineRunnerError.forcedFailure) {
            _ = try await runner.run(
                pipeline: makePipeline(steps: [("Template A", "Prompt A")]),
                transcript: transcript,
                modelID: "qwen3-8b"
            )
        }
    }
}

private func seedTranscript(text: String, in store: TranscriptStore) throws -> TranscriptRecord {
    try store.save(
        TranscriptRecord(
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: nil,
            durationSeconds: 3,
            text: text
        )
    )
}

private func makePipeline(steps: [(name: String, prompt: String)]) -> ExportPipeline {
    ExportPipeline(
        name: "Pipeline",
        steps: steps.enumerated().map { offset, step in
            ExportPipelineStep(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", offset + 1))!,
                templateID: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", offset + 1))!,
                templateName: step.name,
                templatePrompt: step.prompt
            )
        },
        runAutomatically: false,
        outputDestination: .none,
        createdAt: Date(timeIntervalSince1970: 1_710_000_000)
    )
}

private enum MockPipelineRunnerError: Error, Equatable {
    case forcedFailure
}

private final class MockPipelineRunnerLMStudioClient: LMStudioClientProtocol, @unchecked Sendable {
    var responses: [String] = []
    var chatRequests: [ChatCompletionRequest] = []
    var errorAtCallIndex: Int?

    func fetchModels() async throws -> [LMStudioModel] {
        []
    }

    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let callIndex = chatRequests.count
        chatRequests.append(request)

        if errorAtCallIndex == callIndex {
            throw MockPipelineRunnerError.forcedFailure
        }

        let responseText: String
        if responses.indices.contains(callIndex) {
            responseText = responses[callIndex]
        } else {
            responseText = "response-\(callIndex)"
        }

        return ChatCompletionResponse(
            id: "chat-\(callIndex)",
            choices: [
                .init(
                    index: 0,
                    message: .init(role: "assistant", content: responseText),
                    finishReason: "stop"
                ),
            ]
        )
    }

    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
