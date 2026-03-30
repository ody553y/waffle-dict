import Foundation
import Testing
@testable import ScreamerCore

struct TranscriptExporterTests {
    @Test func plainTextExportReturnsTranscriptText() {
        let record = makeRecord(text: "hello world")

        let output = TranscriptExporter.exportAsPlainText(record)

        #expect(output == "hello world")
    }

    @Test func markdownExportIncludesMetadataAndText() {
        let record = makeRecord(text: "meeting notes")

        let output = TranscriptExporter.exportAsMarkdown(record)

        #expect(output.contains("Date:"))
        #expect(output.contains("Source:"))
        #expect(output.contains("Model: whisper-small"))
        #expect(output.contains("meeting notes"))
    }

    @Test func jsonExportRoundTripsRecords() throws {
        let records = [
            makeRecord(id: 1, text: "one"),
            makeRecord(id: 2, text: "two", sourceType: "file_import", sourceFileName: "call.wav"),
        ]

        let data = try TranscriptExporter.exportAsJSON(records)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TranscriptRecord].self, from: data)

        #expect(decoded == records)
    }

    @Test func srtExportUsesSingleSegmentWithDuration() {
        let record = makeRecord(text: "caption text", durationSeconds: 12.345)

        let output = TranscriptExporter.exportAsSRT(record)

        let expected = """
        1
        00:00:00,000 --> 00:00:12,345
        caption text
        """

        #expect(output == expected)
    }

    @Test func vttExportUsesSingleSegmentWithDuration() {
        let record = makeRecord(text: "caption text", durationSeconds: 12.345)

        let output = TranscriptExporter.exportAsVTT(record)

        let expected = """
        WEBVTT

        1
        00:00:00.000 --> 00:00:12.345
        caption text
        """

        #expect(output == expected)
    }

    @Test func srtExportUsesRealSegmentsWhenAvailable() {
        let record = makeRecord(
            text: "caption text",
            durationSeconds: 12.345,
            segments: [
                TranscriptSegment(start: 0.0, end: 1.2, text: "hello"),
                TranscriptSegment(start: 1.2, end: 2.5, text: "world"),
            ]
        )

        let output = TranscriptExporter.exportAsSRT(record, segments: record.segments)

        let expected = """
        1
        00:00:00,000 --> 00:00:01,200
        hello

        2
        00:00:01,200 --> 00:00:02,500
        world
        """

        #expect(output == expected)
    }

    @Test func vttExportUsesRealSegmentsWhenAvailable() {
        let record = makeRecord(
            text: "caption text",
            durationSeconds: 12.345,
            segments: [
                TranscriptSegment(start: 0.0, end: 1.2, text: "hello"),
                TranscriptSegment(start: 1.2, end: 2.5, text: "world"),
            ]
        )

        let output = TranscriptExporter.exportAsVTT(record, segments: record.segments)

        let expected = """
        WEBVTT

        1
        00:00:00.000 --> 00:00:01.200
        hello

        2
        00:00:01.200 --> 00:00:02.500
        world
        """

        #expect(output == expected)
    }

    @Test func srtExportDeduplicatesAdjacentIdenticalSegments() {
        let record = makeRecord(
            text: "caption text",
            durationSeconds: 12.345,
            segments: [
                TranscriptSegment(start: 0.0, end: 1.0, text: "hello"),
                TranscriptSegment(start: 1.0, end: 2.0, text: "hello"),
                TranscriptSegment(start: 2.0, end: 3.0, text: "world"),
            ]
        )

        let output = TranscriptExporter.exportAsSRT(record, segments: record.segments)

        let expected = """
        1
        00:00:00,000 --> 00:00:02,000
        hello

        2
        00:00:02,000 --> 00:00:03,000
        world
        """

        #expect(output == expected)
    }

    @Test func exportDispatcherUsesSegmentsForSRT() throws {
        let record = makeRecord(
            text: "caption text",
            durationSeconds: 12.345,
            segments: [
                TranscriptSegment(start: 0.0, end: 1.2, text: "hello"),
                TranscriptSegment(start: 1.2, end: 2.5, text: "world"),
            ]
        )

        let data = try TranscriptExporter.export(records: [record], format: .srt)
        let output = String(decoding: data, as: UTF8.self)

        #expect(output.contains("1\n00:00:00,000 --> 00:00:01,200\nhello"))
        #expect(output.contains("2\n00:00:01,200 --> 00:00:02,500\nworld"))
    }
}

private func makeRecord(
    id: Int64? = nil,
    text: String,
    sourceType: String = "dictation",
    sourceFileName: String? = nil,
    durationSeconds: Double? = 5.2,
    segments: [TranscriptSegment]? = nil
) -> TranscriptRecord {
    TranscriptRecord(
        id: id,
        createdAt: Date(timeIntervalSince1970: 1_710_000_000),
        sourceType: sourceType,
        sourceFileName: sourceFileName,
        modelID: "whisper-small",
        languageHint: "en",
        durationSeconds: durationSeconds,
        text: text,
        segments: segments
    )
}
