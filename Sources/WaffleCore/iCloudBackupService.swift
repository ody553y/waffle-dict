import Foundation

public final class iCloudBackupService: @unchecked Sendable {
    public typealias ContainerURLProvider = @Sendable (_ containerIdentifier: String, _ fileManager: FileManager) -> URL?

    private let containerIdentifier: String
    private let archiver: TranscriptArchiver
    private let fileManager: FileManager
    private let containerURLProvider: ContainerURLProvider
    private let appVersionProvider: @Sendable () -> String

    public init(
        containerIdentifier: String = "iCloud.com.waffle.app",
        archiver: TranscriptArchiver = TranscriptArchiver(),
        fileManager: FileManager = .default,
        containerURLProvider: @escaping ContainerURLProvider = { identifier, fileManager in
            fileManager.url(forUbiquityContainerIdentifier: identifier)
        },
        appVersionProvider: (@Sendable () -> String)? = nil
    ) {
        self.containerIdentifier = containerIdentifier
        self.archiver = archiver
        self.fileManager = fileManager
        self.containerURLProvider = containerURLProvider
        self.appVersionProvider = appVersionProvider ?? defaultICloudBackupAppVersion
    }

    public var isAvailable: Bool {
        containerURL != nil
    }

    public var containerURL: URL? {
        guard let root = containerURLProvider(containerIdentifier, fileManager) else {
            return nil
        }
        return root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
    }

    public func backup(transcript: TranscriptRecord, actions: [TranscriptActionRecord]) throws {
        guard let container = containerURL else { return }

        try fileManager.createDirectory(at: container, withIntermediateDirectories: true)

        let archive = WaffleArchive(
            version: TranscriptArchiver.currentArchiveVersion,
            exportedAt: Date(),
            appVersion: appVersionProvider(),
            transcripts: [ArchivedTranscript(record: transcript, actions: actions)]
        )

        let destination = container.appendingPathComponent(backupFilename(for: transcript))
        try archiver.write(archive, to: destination)
    }

    public func listBackups() throws -> [URL] {
        guard let container = containerURL else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return files
            .filter { $0.pathExtension.lowercased() == "waffle" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast

                if lhsDate == rhsDate {
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }
                return lhsDate > rhsDate
            }
    }

    public func deleteBackup(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func backupFilename(for transcript: TranscriptRecord) -> String {
        let date = Self.backupDateFormatter.string(from: transcript.createdAt)
        let modelID = sanitizedFilenameComponent(transcript.modelID)
        return "\(date)_\(modelID)-transcript.waffle"
    }
}

private extension iCloudBackupService {
    static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func sanitizedFilenameComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "model" }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()

        let collapsed = mapped
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed.isEmpty ? "model" : collapsed
    }
}

private func defaultICloudBackupAppVersion() -> String {
    guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
        return "unknown"
    }
    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "unknown" : trimmed
}
