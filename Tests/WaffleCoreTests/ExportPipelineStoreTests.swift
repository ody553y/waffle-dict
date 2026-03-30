import Foundation
import Testing
@testable import WaffleCore

struct ExportPipelineStoreTests {
    @Test func loadReturnsEmptyArrayWhenStorageKeyMissing() {
        let (store, _) = makeStore()

        let loaded = store.load()

        #expect(loaded.isEmpty)
    }

    @Test func addEnforcesMaximumPipelineCount() {
        let (store, _) = makeStore()

        for index in 0..<(ExportPipelineStore.maxPipelineCount + 2) {
            store.add(makePipeline(index: index))
        }

        let loaded = store.load()
        #expect(loaded.count == ExportPipelineStore.maxPipelineCount)
    }

    @Test func deleteRemovesPipelineByID() {
        let (store, _) = makeStore()
        let first = makePipeline(index: 1)
        let second = makePipeline(index: 2)
        store.save([first, second])

        store.delete(id: first.id)

        let loaded = store.load()
        #expect(loaded == [second])
    }

    @Test func updateReplacesExistingPipeline() {
        let (store, _) = makeStore()
        var pipeline = makePipeline(index: 1)
        store.save([pipeline])

        pipeline.name = "Updated Name"
        pipeline.runAutomatically = true
        pipeline.outputDestination = .clipboard
        pipeline.steps.append(
            ExportPipelineStep(
                templateID: UUID(uuidString: "99999999-0000-0000-0000-000000000000")!,
                templateName: "Template 2",
                templatePrompt: "Prompt 2"
            )
        )
        store.update(pipeline)

        let loaded = store.load()
        #expect(loaded == [pipeline])
    }

    @Test func exportPipelineAndStepJSONRoundTrip() throws {
        let pipeline = makePipeline(index: 7)

        let encoded = try JSONEncoder().encode(pipeline)
        let decoded = try JSONDecoder().decode(ExportPipeline.self, from: encoded)

        #expect(decoded == pipeline)
    }
}

private func makeStore() -> (ExportPipelineStore, UserDefaults) {
    let suiteName = "ExportPipelineStoreTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let store = ExportPipelineStore(userDefaults: userDefaults)
    return (store, userDefaults)
}

private func makePipeline(index: Int) -> ExportPipeline {
    let templateID = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    let pipelineID = UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 1))!
    return ExportPipeline(
        id: pipelineID,
        name: "Pipeline \(index)",
        steps: [
            ExportPipelineStep(
                id: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", index + 1))!,
                templateID: templateID,
                templateName: "Template \(index)",
                templatePrompt: "Prompt \(index)"
            ),
        ],
        runAutomatically: false,
        outputDestination: .none,
        createdAt: Date(timeIntervalSince1970: 1_710_000_000 + TimeInterval(index))
    )
}
