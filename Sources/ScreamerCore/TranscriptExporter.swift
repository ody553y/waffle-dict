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
        lines.append(record.text)

        return lines.joined(separator: "\n")
    }

    public static func exportAsJSON(_ records: [TranscriptRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    public static func exportAsSRT(_ record: TranscriptRecord) -> String {
        let end = formatSRTTime(record.durationSeconds ?? 0)
        return """
        1
        00:00:00,000 --> \(end)
        \(record.text)
        """
    }

    public static func exportAsVTT(_ record: TranscriptRecord) -> String {
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
            return Data(exportAsSRT(record).utf8)
        case .vtt:
            guard let record = records.first else { return Data() }
            return Data(exportAsVTT(record).utf8)
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

    static func formatTime(seconds: Double, separator: String) -> String {
        let millisecondsTotal = Int((max(seconds, 0) * 1000).rounded())
        let hours = millisecondsTotal / 3_600_000
        let minutes = (millisecondsTotal % 3_600_000) / 60_000
        let secs = (millisecondsTotal % 60_000) / 1_000
        let milliseconds = millisecondsTotal % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, milliseconds)
    }
}
