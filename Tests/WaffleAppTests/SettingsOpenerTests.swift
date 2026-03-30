import AppKit
import Testing
@testable import WaffleApp

@MainActor
struct SettingsOpenerTests {
    @Test func openUsesShowSettingsActionWhenAvailable() {
        var openSettingsCallCount = 0
        var activateCalls: [Bool] = []
        var sendActionCallCount = 0

        SettingsOpener.open(
            openSettings: { openSettingsCallCount += 1 },
            activate: { activateCalls.append($0) },
            sendAction: { action, _, _ in
                sendActionCallCount += 1
                #expect(NSStringFromSelector(action) == "showSettingsWindow:")
                return true
            }
        )

        #expect(sendActionCallCount == 1)
        #expect(openSettingsCallCount == 0)
        #expect(activateCalls == [true, true])
    }

    @Test func openFallsBackToSwiftUIOpenSettingsWhenActionUnavailable() {
        var openSettingsCallCount = 0
        var activateCalls: [Bool] = []
        var sendActionCallCount = 0

        SettingsOpener.open(
            openSettings: { openSettingsCallCount += 1 },
            activate: { activateCalls.append($0) },
            sendAction: { _, _, _ in
                sendActionCallCount += 1
                return false
            }
        )

        #expect(sendActionCallCount == 1)
        #expect(openSettingsCallCount == 1)
        #expect(activateCalls == [true, true])
    }
}
