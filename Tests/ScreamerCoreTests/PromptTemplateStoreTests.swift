import Foundation
import Testing
@testable import ScreamerCore

struct PromptTemplateStoreTests {
    @Test func loadSeedsDefaultTemplatesWhenStorageKeyIsMissing() {
        let (store, userDefaults) = makeStore()

        let loaded = store.load()

        #expect(loaded.count == 3)
        #expect(loaded.map(\.name) == ["Bullet Summary", "Action Items", "Key Topics"])
        #expect(userDefaults.data(forKey: PromptTemplateStore.storageKey) != nil)
    }

    @Test func loadDoesNotReseedWhenStorageKeyExistsWithEmptyArray() throws {
        let (store, userDefaults) = makeStore()
        let emptyData = try JSONEncoder().encode([PromptTemplate]())
        userDefaults.set(emptyData, forKey: PromptTemplateStore.storageKey)

        let loaded = store.load()

        #expect(loaded.isEmpty)
    }

    @Test func addUpdateDeleteRoundTripPersistsTemplates() throws {
        let (store, _) = makeStore()

        _ = store.load()
        let created = store.add(
            name: "Decisions",
            prompt: "Extract decisions and owners from this transcript."
        )

        var afterAdd = store.load()
        #expect(afterAdd.contains(where: { $0.id == created.id }))

        var updated = try #require(afterAdd.first(where: { $0.id == created.id }))
        updated.name = "Decision Log"
        updated.prompt = "List decisions with responsible owners and due dates."
        store.update(updated)

        afterAdd = store.load()
        let persisted = try #require(afterAdd.first(where: { $0.id == created.id }))
        #expect(persisted.name == "Decision Log")
        #expect(persisted.prompt == "List decisions with responsible owners and due dates.")

        store.delete(id: created.id)
        let afterDelete = store.load()
        #expect(afterDelete.contains(where: { $0.id == created.id }) == false)
    }

    @Test func saveAndLoadPreserveUUIDAndDateFields() {
        let (store, _) = makeStore()
        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
        let id = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let input = PromptTemplate(
            id: id,
            name: "Stable Template",
            prompt: "Use exact values.",
            createdAt: createdAt
        )

        store.save([input])
        let output = store.load()

        #expect(output == [input])
    }
}

private func makeStore() -> (PromptTemplateStore, UserDefaults) {
    let suiteName = "PromptTemplateStoreTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    let store = PromptTemplateStore(userDefaults: userDefaults)
    return (store, userDefaults)
}
