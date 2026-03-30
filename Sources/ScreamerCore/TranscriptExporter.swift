import Foundation

public enum TranscriptExportFormat: String, CaseIterable, Sendable {
    case plainText
    case markdown
    case json
    case srt
    case vtt

    public var displayName: String {
        switch self {
        case .plainText:
            return "Plain Text"
        case .markdown:
            return "Markdown"
        case .json:
            return "JSON"
        case .srt:
            return "SRT"
        case .vtt:
            return "VTT"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plainText:
            return "txt"
        case .markdown:
            return "md"
        case .json:
            return "json"
        case .srt:
            return "srt"
        case .vtt:
            return "vtt"
        }
    }
}

public enum TranscriptExporter {
    public static func exportAsPlainText(_ record: TranscriptRecord) -> String {
        record.text
    }

    public static func exportAsMarkdown(_ record: TranscriptRecord) -> String {
        let date = markdownDateFormatter.string(from: record.createdAt)
        let source = sourceDisplayName(for: record)

        var lines: [String] = [
            "# Transcript",
            "",
            "- Date: \(date)",
            "- Source: \(source)",
            "- Model: \(record.modelID)",
        ]

        if let languageHint = record.languageHint, languageHint.isEmpty == false {
            lines.append("- Language Hint: \(languageHint)")
        }

        if let duration = record.durationSeconds {
            lines.append("- Duration Seconds: \(String(format: "%.3f", duration))")
        }

        lines.append("")
        if let dialogueLines = markdownDialogueLines(from: record.segments) {
            lines.append(contentsOf: dialogueLines)
        } else {
            lines.append(record.text)
        }

        return lines.joined(separator: "\n")
    }

    public static func exportAsJSON(_ records: [TranscriptRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    public static func exportAsSRT(
        _ record: TranscriptRecord,
        segments: [TranscriptSegment]? = nil
    ) -> String {
        if let cues = formattedCues(from: segments ?? record.segments, separator: ","),
           cues.isEmpty == false {
            return cues
        }

        let end = formatSRTTime(record.durationSeconds ?? 0)
        return """
        1
        00:00:00,000 --> \(end)
        \(record.text)
        """
    }

    public static func exportAsVTT(
        _ record: TranscriptRecord,
        segments: [TranscriptSegment]? = nil
    ) -> String {
        if let cues = formattedCues(from: segments ?? record.segments, separator: "."),
           cues.isEmpty == false {
            return """
            WEBVTT

            \(cues)
            """
        }

        let end = formatVTTTime(record.durationSeconds ?? 0)
        return """
        WEBVTT

        1
        00:00:00.000 --> \(end)
        \(record.text)
        """
    }

    public static func export(
        records: [TranscriptRecord],
        format: TranscriptExportFormat
    ) throws -> Data {
        switch format {
        case .json:
            return try exportAsJSON(records)
        case .plainText:
            guard let record = records.first else { return Data() }
            return Data(exportAsPlainText(record).utf8)
        case .markdown:
            guard let record = records.first else { return Data() }
            return Data(exportAsMarkdown(record).utf8)
        case .srt:
            guard let record = records.first else { return Data() }
            return Data(exportAsSRT(record, segments: record.segments).utf8)
        case .vtt:
            guard let record = records.first else { return Data() }
            return Data(exportAsVTT(record, segments: record.segments).utf8)
        }
    }
}

private extension TranscriptExporter {
    static let markdownDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static func sourceDisplayName(for record: TranscriptRecord) -> String {
        if record.sourceType == "dictation" {
            return "Dictation"
        }
        if let sourceFileName = record.sourceFileName, sourceFileName.isEmpty == false {
            return sourceFileName
        }
        return "Imported File"
    }

    static func formatSRTTime(_ seconds: Double) -> String {
        formatTime(seconds: seconds, separator: ",")
    }

    static func formatVTTTime(_ seconds: Double) -> String {
        formatTime(seconds: seconds, separator: ".")
    }

    static func formattedCues(
        from segments: [TranscriptSegment]?,
        separator: String
    ) -> String? {
        guard let segments, segments.isEmpty == false else {
            return nil
        }

        let dedupedSegments = deduplicateAdjacentSegments(segments)
        guard dedupedSegments.isEmpty == false else {
            return nil
        }

        return dedupedSegments.enumerated().map { index, segment in
            let start = formatTime(seconds: segment.start, separator: separator)
            let end = formatTime(seconds: segment.end, separator: separator)
            return """
            \(index + 1)
            \(start) --> \(end)
            \(cueText(for: segment))
            """
        }
        .joined(separator: "\n\n")
    }

    static func deduplicateAdjacentSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard segments.isEmpty == false else {
            return []
        }

        var deduped: [TranscriptSegment] = []
        deduped.reserveCapacity(segments.count)

        for segment in segments {
            let normalizedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = deduped.last,
               last.text.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedText,
               normalizedSpeakerLabel(last.speaker) == normalizedSpeakerLabel(segment.speaker) {
                deduped[deduped.count - 1] = TranscriptSegment(
                    start: last.start,
                    end: max(last.end, segment.end),
                    text: last.text,
                    speaker: last.speaker
                )
            } else {
                deduped.append(segment)
            }
        }

        return deduped
    }

    static func cueText(for segment: TranscriptSegment) -> String {
        guard let speaker = normalizedSpeakerLabel(segment.speaker) else {
            return segment.text
        }
        return "\(speaker): \(segment.text)"
    }

    static func normalizedSpeakerLabel(_ speaker: String?) -> String? {
        guard let speaker else { return nil }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func markdownDialogueLines(from segments: [TranscriptSegment]?) -> [String]? {
        guard let segments, segments.isEmpty == false else {
            return nil
        }

        let hasSpeakers = segments.contains { normalizedSpeakerLabel($0.speaker) != nil }
        guard hasSpeakers else {
            return nil
        }

        var lines: [String] = []
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { continue }
            let timestamp = markdownDialogueTimestamp(for: segment.start)

            if let speaker = normalizedSpeakerLabel(segment.speaker) {
                lines.append("**\(speaker)** (\(timestamp)): \(text)")
            } else {
                lines.append("(\(timestamp)): \(text)")
            }
            lines.append("")
        }

        if lines.last == "" {
            lines.removeLast()
        }

        return lines.isEmpty ? nil : lines
    }

    static func markdownDialogueTimestamp(for seconds: Double) -> String {
        let totalSeconds = Int(max(seconds, 0))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%d:%02d", minutes, secs)
    }

    static func formatTime(seconds: Double, separator: String) -> String {
        let millisecondsTotal = Int((max(seconds, 0) * 1000).rounded())
        let hours = millisecondsTotal / 3_600_000
        let minutes = (millisecondsTotal % 3_600_000) / 60_000
        let secs = (millisecondsTotal % 60_000) / 1_000
        let milliseconds = millisecondsTotal % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, milliseconds)
    }
}
