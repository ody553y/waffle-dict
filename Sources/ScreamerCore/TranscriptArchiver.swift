import Foundation

public struct ScreamerArchive: Codable, Equatable, Sendable {
    public let version: Int
    public let exportedAt: Date
    public let appVersion: String
    public var transcripts: [ArchivedTranscript]

    public init(
        version: Int,
        exportedAt: Date,
        appVersion: String,
        transcripts: [ArchivedTranscript]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.transcripts = transcripts
    }
}

public struct ArchivedTranscript: Codable, Equatable, Sendable {
    public var record: TranscriptRecord
    public var actions: [TranscriptActionRecord]

    public init(record: TranscriptRecord, actions: [TranscriptActionRecord]) {
        self.record = record
        self.actions = actions
    }
}

public enum ArchiveError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Archive version \(version) is not supported by this app version."
        case .invalidData(let message):
            return "Archive data is invalid: \(message)"
        }
    }
}

public struct TranscriptArchiver: Sendable {
    public static let currentArchiveVersion = 1
    private let appVersionProvider: @Sendable () -> String

    public init(appVersionProvider: @escaping @Sendable () -> String = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value ?? "unknown" : "unknown"
    }) {
        self.appVersionProvider = appVersionProvider
    }

    public func export(transcripts: [TranscriptRecord], store: TranscriptStore) throws -> Data {
        let archivedTranscripts = try transcripts.map { transcript in
            let actions: [TranscriptActionRecord]
            if let transcriptID = transcript.id {
                actions = try store.fetchActions(forTranscriptID: transcriptID)
            } else {
                actions = []
            }
            return ArchivedTranscript(record: transcript, actions: actions)
        }

        let archive = ScreamerArchive(
            version: Self.currentArchiveVersion,
            exportedAt: Date(),
            appVersion: appVersionProvider(),
            transcripts: archivedTranscripts
        )
        return try Self.makeEncoder().encode(archive)
    }

    public func `import`(from data: Data) throws -> ScreamerArchive {
        let archive: ScreamerArchive
        do {
            archive = try Self.makeDecoder().decode(ScreamerArchive.self, from: data)
        } catch {
            throw ArchiveError.invalidData(error.localizedDescription)
        }

        guard archive.version <= Self.currentArchiveVersion else {
            throw ArchiveError.unsupportedVersion(archive.version)
        }

        return archive
    }

    public func write(_ archive: ScreamerArchive, to url: URL) throws {
        let data: Data
        do {
            data = try Self.makeEncoder().encode(archive)
        } catch {
            throw ArchiveError.invalidData(error.localizedDescription)
        }
        try data.write(to: url, options: .atomic)
    }

    public func read(from url: URL) throws -> ScreamerArchive {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ArchiveError.invalidData(error.localizedDescription)
        }
        return try `import`(from: data)
    }
}

private extension TranscriptArchiver {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
