import Testing
@testable import WaffleApp
@testable import WaffleCore

@Suite
struct SegmentEditorSheetTests {
    @Test func formatTimeFormatsSubMinuteValuesAsSeconds() {
        #expect(SegmentEditorSheet.formatTime(0) == "0s")
        #expect(SegmentEditorSheet.formatTime(59.9) == "59s")
    }

    @Test func formatTimeFormatsMinuteAndGreaterValuesAsClockTime() {
        #expect(SegmentEditorSheet.formatTime(60) == "01:00")
        #expect(SegmentEditorSheet.formatTime(125) == "02:05")
    }

    @Test func editableSegmentConvertsToTranscriptSegmentWithNormalizedSpeaker() {
        let editable = EditableSegment(
            start: 3.0,
            end: 5.5,
            text: "hello there",
            speaker: "  Alice  "
        )

        let converted = editable.transcriptSegment
        #expect(converted.start == 3.0)
        #expect(converted.end == 5.5)
        #expect(converted.text == "hello there")
        #expect(converted.speaker == "Alice")
    }

    @Test func editableSegmentConvertsBlankSpeakerToNil() {
        let editable = EditableSegment(
            start: 0.0,
            end: 1.0,
            text: "test",
            speaker: "   "
        )

        #expect(editable.transcriptSegment.speaker == nil)
    }
}
