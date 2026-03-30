import Foundation

public enum ExportPipelineError: Error, Equatable, Sendable {
    case emptyPipeline
}

public final class ExportPipelineRunner: Sendable {
    private let actionService: TranscriptActionService
    private let transcriptStore: TranscriptStore

    public init(
        actionService: TranscriptActionService,
        transcriptStore: TranscriptStore
    ) {
        self.actionService = actionService
        self.transcriptStore = transcriptStore
    }

    public func run(
        pipeline: ExportPipeline,
        transcript: TranscriptRecord,
        modelID: String
    ) async throws -> String {
        guard pipeline.steps.isEmpty == false else {
            throw ExportPipelineError.emptyPipeline
        }

        var currentText = transcript.text

        for step in pipeline.steps {
            var scratchTranscript = transcript
            scratchTranscript.text = currentText

            let result = try await actionService.perform(
                action: .customPrompt(prompt: step.templatePrompt),
                on: scratchTranscript,
                modelID: modelID
            )

            _ = try transcriptStore.saveAction(
                TranscriptActionRecord(
                    transcriptID: result.sourceTranscriptID,
                    createdAt: result.createdAt,
                    actionType: "pipeline_step",
                    actionInput: step.templateName,
                    llmModelID: result.modelUsed,
                    resultText: result.resultText
                )
            )

            currentText = result.resultText
        }

        return currentText
    }
}
