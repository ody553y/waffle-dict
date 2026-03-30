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
    public static func exportAsPlainText(
        _ record: TranscriptRecord,
        speakerMap: [String: String]? = nil
    ) -> String {
        if let dialogueLines = plainTextDialogueLines(
            from: record.segments,
            speakerMap: speakerMap ?? record.speakerMap
        ) {
            return dialogueLines.joined(separator: "\n")
        }
        return record.text
    }

    public static func exportAsMarkdown(
        _ record: TranscriptRecord,
        speakerMap: [String: String]? = nil
    ) -> String {
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
        if let dialogueLines = markdownDialogueLines(
            from: record.segments,
            speakerMap: speakerMap ?? record.speakerMap
        ) {
            lines.append(contentsOf: dialogueLines)
        } else {
            lines.append(record.text)
        }

        return lines.joined(separator: "\n")
    }

    public static func exportAsJSON(
        _ records: [TranscriptRecord],
        speakerMap: [String: String]? = nil
    ) throws -> Data {
        let exportRecords = records.map { record in
            let resolvedMap = speakerMap ?? record.speakerMap
            return TranscriptJSONExportRecord(
                id: record.id,
                createdAt: record.createdAt,
                sourceType: record.sourceType,
                sourceFileName: record.sourceFileName,
                modelID: record.modelID,
                languageHint: record.languageHint,
                durationSeconds: record.durationSeconds,
                text: record.text,
                segments: record.segments?.map { segment in
                    TranscriptJSONExportSegment(
                        start: segment.start,
                        end: segment.end,
                        text: segment.text,
                        speaker: normalizedSpeakerLabel(segment.speaker),
                        displaySpeaker: resolvedSpeaker(
                            rawSpeaker: segment.speaker,
                            speakerMap: resolvedMap
                        )
                    )
                },
                speakerMap: record.speakerMap,
                notes: record.notes
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportRecords)
    }

    public static func exportAsSRT(
        _ record: TranscriptRecord,
        segments: [TranscriptSegment]? = nil,
        speakerMap: [String: String]? = nil
    ) -> String {
        if let cues = formattedCues(
            from: segments ?? record.segments,
            separator: ",",
            speakerMap: speakerMap ?? record.speakerMap
        ),
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
        segments: [TranscriptSegment]? = nil,
        speakerMap: [String: String]? = nil
    ) -> String {
        if let cues = formattedCues(
            from: segments ?? record.segments,
            separator: ".",
            speakerMap: speakerMap ?? record.speakerMap
        ),
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
        format: TranscriptExportFormat,
        speakerMap: [String: String]? = nil
    ) throws -> Data {
        if records.count > 1 {
            switch format {
            case .json:
                return try exportAsJSON(records)
            case .plainText, .markdown, .srt, .vtt:
                let batchOutput = batchTextExport(records: records, format: format)
                return Data(batchOutput.utf8)
            }
        }

        switch format {
        case .json:
            return try exportAsJSON(records, speakerMap: speakerMap)
        case .plainText:
            guard let record = records.first else { return Data() }
            return Data(exportAsPlainText(record, speakerMap: speakerMap).utf8)
        case .markdown:
            guard let record = records.first else { return Data() }
            return Data(exportAsMarkdown(record, speakerMap: speakerMap).utf8)
        case .srt:
            guard let record = records.first else { return Data() }
            return Data(exportAsSRT(record, segments: record.segments, speakerMap: speakerMap).utf8)
        case .vtt:
            guard let record = records.first else { return Data() }
            return Data(exportAsVTT(record, segments: record.segments, speakerMap: speakerMap).utf8)
        }
    }
}

private extension TranscriptExporter {
    struct TranscriptJSONExportRecord: Encodable {
        let id: Int64?
        let createdAt: Date
        let sourceType: String
        let sourceFileName: String?
        let modelID: String
        let languageHint: String?
        let durationSeconds: Double?
        let text: String
        let segments: [TranscriptJSONExportSegment]?
        let speakerMap: [String: String]?
        let notes: String?
    }

    struct TranscriptJSONExportSegment: Encodable {
        let start: Double
        let end: Double
        let text: String
        let speaker: String?
        let displaySpeaker: String?
    }

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
        separator: String,
        speakerMap: [String: String]?
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
            \(cueText(for: segment, speakerMap: speakerMap))
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

    static func cueText(for segment: TranscriptSegment, speakerMap: [String: String]?) -> String {
        guard let speaker = resolvedSpeaker(rawSpeaker: segment.speaker, speakerMap: speakerMap) else {
            return segment.text
        }
        return "\(speaker): \(segment.text)"
    }

    static func normalizedSpeakerLabel(_ speaker: String?) -> String? {
        guard let speaker else { return nil }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func markdownDialogueLines(
        from segments: [TranscriptSegment]?,
        speakerMap: [String: String]?
    ) -> [String]? {
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

            if let speaker = resolvedSpeaker(rawSpeaker: segment.speaker, speakerMap: speakerMap) {
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

    static func plainTextDialogueLines(
        from segments: [TranscriptSegment]?,
        speakerMap: [String: String]?
    ) -> [String]? {
        guard let segments, segments.isEmpty == false else { return nil }
        let hasSpeakers = segments.contains { normalizedSpeakerLabel($0.speaker) != nil }
        guard hasSpeakers else { return nil }

        let lines: [String] = segments.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { return nil }
            if let speaker = resolvedSpeaker(rawSpeaker: segment.speaker, speakerMap: speakerMap) {
                return "\(speaker): \(text)"
            }
            return text
        }

        return lines.isEmpty ? nil : lines
    }

    static func resolvedSpeaker(rawSpeaker: String?, speakerMap: [String: String]?) -> String? {
        guard let normalizedRawSpeaker = normalizedSpeakerLabel(rawSpeaker) else { return nil }
        if let mappedSpeaker = normalizedSpeakerLabel(speakerMap?[normalizedRawSpeaker]) {
            return mappedSpeaker
        }
        return normalizedRawSpeaker
    }

    static func batchTextExport(records: [TranscriptRecord], format: TranscriptExportFormat) -> String {
        records.map { record in
            let content: String
            switch format {
            case .plainText:
                content = exportAsPlainText(record, speakerMap: record.speakerMap)
            case .markdown:
                content = exportAsMarkdown(record, speakerMap: record.speakerMap)
            case .srt:
                content = exportAsSRT(record, segments: record.segments, speakerMap: record.speakerMap)
            case .vtt:
                content = exportAsVTT(record, segments: record.segments, speakerMap: record.speakerMap)
            case .json:
                content = record.text
            }

            return """
            \(batchHeader(for: record))

            \(content)
            """
        }
        .joined(separator: "\n\n---\n\n")
    }

    static func batchHeader(for record: TranscriptRecord) -> String {
        """
        Date: \(markdownDateFormatter.string(from: record.createdAt))
        Source: \(sourceDisplayName(for: record))
        Model: \(record.modelID)
        """
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
