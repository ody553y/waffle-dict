import Foundation

public enum ModelFamily: String, Codable, Sendable {
    case whisper
    case parakeet
}

public struct ModelCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let family: ModelFamily
    public let displayName: String
    public let sizeMB: Int
    public let languages: [String]
    public let supportsLive: Bool
    public let supportsTranslation: Bool
    public let downloadURL: URL
    public let sha256Checksum: String
    public let available: Bool

    public init(
        id: String,
        family: ModelFamily,
        displayName: String,
        sizeMB: Int,
        languages: [String],
        supportsLive: Bool,
        supportsTranslation: Bool,
        downloadURL: URL,
        sha256Checksum: String,
        available: Bool = true
    ) {
        self.id = id
        self.family = family
        self.displayName = displayName
        self.sizeMB = sizeMB
        self.languages = languages
        self.supportsLive = supportsLive
        self.supportsTranslation = supportsTranslation
        self.downloadURL = downloadURL
        self.sha256Checksum = sha256Checksum
        self.available = available
    }

    enum CodingKeys: String, CodingKey {
        case id
        case family
        case displayName = "display_name"
        case sizeMB = "size_mb"
        case languages
        case supportsLive = "supports_live"
        case supportsTranslation = "supports_translation"
        case downloadURL = "download_url"
        case sha256Checksum = "sha256_checksum"
        case available
    }

    public var languageCount: Int {
        languages.count
    }

    public var workerModelID: String {
        guard family == .whisper, id.hasPrefix("whisper-") else {
            return id
        }
        return String(id.dropFirst("whisper-".count))
    }
}

public final class ModelCatalogService: @unchecked Sendable {
    private let manifestDataLoader: @Sendable () throws -> Data
    private let fileManager: FileManager
    private let applicationSupportDirectory: URL

    public init(
        manifestDataLoader: (@Sendable () throws -> Data)? = nil,
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.manifestDataLoader = manifestDataLoader ?? {
            guard let url = Bundle.module.url(forResource: "models-manifest", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try Data(contentsOf: url)
        }
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory ?? defaultApplicationSupportDirectory(
            fileManager: fileManager
        )
    }

    public func loadCatalog() throws -> [ModelCatalogEntry] {
        let decoder = JSONDecoder()
        return try decoder.decode([ModelCatalogEntry].self, from: manifestDataLoader())
    }

    public func installedModels() -> [String] {
        let modelsDirectory = modelsDirectoryURL()
        guard
            let directoryContents = try? fileManager.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return directoryContents.compactMap { candidate in
            guard
                let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory == true,
                let installedFiles = try? fileManager.contentsOfDirectory(
                    at: candidate,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ),
                installedFiles.isEmpty == false
            else {
                return nil
            }
            return candidate.lastPathComponent
        }
        .sorted()
    }

    public func isInstalled(id: String) -> Bool {
        installedModels().contains(id)
    }

    public func installPath(for id: String) -> URL {
        modelsDirectoryURL().appending(path: id, directoryHint: .isDirectory)
    }

    public func removeInstalledModel(id: String) throws {
        let path = installPath(for: id)
        guard fileManager.fileExists(atPath: path.path) else {
            return
        }
        try fileManager.removeItem(at: path)
    }

    public func resolveSelectedModelID(currentSelection: String?) -> String? {
        let installed = installedModels()
        guard installed.isEmpty == false else {
            return nil
        }

        if let currentSelection, installed.contains(currentSelection) {
            return currentSelection
        }
        if installed.contains("whisper-small") {
            return "whisper-small"
        }
        return installed.first
    }

    public func installedEntries(from catalog: [ModelCatalogEntry]) -> [ModelCatalogEntry] {
        let installed = Set(installedModels())
        return catalog.filter { installed.contains($0.id) }
    }

    public func modelsDirectoryURL() -> URL {
        let url = applicationSupportDirectory
            .appending(path: "Screamer", directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
        ensureDirectoryExists(at: url)
        return url
    }

    public func downloadsDirectoryURL() -> URL {
        let url = applicationSupportDirectory
            .appending(path: "Screamer", directoryHint: .isDirectory)
            .appending(path: "Downloads", directoryHint: .isDirectory)
        ensureDirectoryExists(at: url)
        return url
    }

    private func ensureDirectoryExists(at url: URL) {
        if fileManager.fileExists(atPath: url.path) == false {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private func defaultApplicationSupportDirectory(fileManager: FileManager) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
}
