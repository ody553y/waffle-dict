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
}

private func makeRecord(
    id: Int64? = nil,
    text: String,
    sourceType: String = "dictation",
    sourceFileName: String? = nil,
    durationSeconds: Double? = 5.2
) -> TranscriptRecord {
    TranscriptRecord(
        id: id,
        createdAt: Date(timeIntervalSince1970: 1_710_000_000),
        sourceType: sourceType,
        sourceFileName: sourceFileName,
        modelID: "whisper-small",
        languageHint: "en",
        durationSeconds: durationSeconds,
        text: text
    )
}
