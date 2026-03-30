import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct WebhookDeliveryLogTests {
    @Test func appendTrimsToTenEntries() {
        let defaults = makeDefaults()
        let log = WebhookDeliveryLog(userDefaults: defaults)

        for index in 0..<12 {
            log.append(
                WebhookDeliveryEntry(
                    id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!,
                    deliveredAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    event: "transcript.created",
                    statusCode: 200,
                    succeeded: true,
                    errorMessage: nil
                )
            )
        }

        let entries = log.load()
        #expect(entries.count == 10)
        #expect(entries.first?.deliveredAt == Date(timeIntervalSince1970: 2))
        #expect(entries.last?.deliveredAt == Date(timeIntervalSince1970: 11))
    }

    @Test func entryJSONRoundTripPreservesFields() throws {
        let entry = WebhookDeliveryEntry(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            deliveredAt: Date(timeIntervalSince1970: 1_710_000_000),
            event: "test",
            statusCode: nil,
            succeeded: false,
            errorMessage: "timed out"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WebhookDeliveryEntry.self, from: data)

        #expect(decoded == entry)
    }

    @Test func clearRemovesAllEntries() {
        let defaults = makeDefaults()
        let log = WebhookDeliveryLog(userDefaults: defaults)
        log.append(
            WebhookDeliveryEntry(
                deliveredAt: Date(),
                event: "test",
                statusCode: 200,
                succeeded: true,
                errorMessage: nil
            )
        )
        #expect(log.load().isEmpty == false)

        log.clear()

        #expect(log.load().isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WebhookDeliveryLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
