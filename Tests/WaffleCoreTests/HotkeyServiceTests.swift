import Carbon.HIToolbox
import Testing
@testable import WaffleCore

struct HotkeyServiceTests {
    @Test func globalHotkeyJSONRoundTrips() throws {
        let hotkey = GlobalHotkey(
            keyCode: CGKeyCode(kVK_ANSI_K),
            modifiers: [.maskCommand, .maskShift],
            displayValue: "⇧⌘K"
        )

        let encoded = try #require(hotkey.encodedJSONString())
        let decoded = try #require(GlobalHotkey.decoded(from: encoded))

        #expect(decoded == hotkey)
        #expect(decoded.storagePayload.keyCode == UInt16(kVK_ANSI_K))
        #expect(decoded.storagePayload.modifiers == hotkey.modifiers.rawValue)
        #expect(decoded.storagePayload.displayValue == "⇧⌘K")
    }

    @Test func globalHotkeyDecodeReturnsNilForInvalidJSON() {
        #expect(GlobalHotkey.decoded(from: "not-json") == nil)
    }
}
