import CryptoKit
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

public struct SignedModelManifest: Codable, Sendable {
    public let manifestVersion: Int
    public let signedAt: String
    public let signature: String
    public let models: [ModelCatalogEntry]

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case signedAt = "signed_at"
        case signature
        case models
    }
}

public enum ManifestVerificationError: Error, Equatable {
    case invalidSignature
    case unsupportedVersion
    case malformedManifest
}

public struct ManifestVerifier: Sendable {
    public static let publicKeyHex =
        "ead1e8b42a7a112caa309c15b0ab735865408220790a85ce4cd482726f48efed"

    private let publicKeyHex: String

    public init(publicKeyHex: String = Self.publicKeyHex) {
        self.publicKeyHex = publicKeyHex
    }

    public func verify(manifest: SignedModelManifest) throws -> Bool {
        guard manifest.manifestVersion == 2 else {
            throw ManifestVerificationError.unsupportedVersion
        }

        guard
            let signatureData = manifest.signature.hexDecodedData(),
            let publicKeyData = publicKeyHex.hexDecodedData(),
            publicKeyData.count == 32
        else {
            throw ManifestVerificationError.malformedManifest
        }

        let payload = try Self.normalizedModelsData(manifest.models)
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw ManifestVerificationError.malformedManifest
        }

        guard publicKey.isValidSignature(signatureData, for: payload) else {
            throw ManifestVerificationError.invalidSignature
        }
        return true
    }

    static func normalizedModelsData(_ models: [ModelCatalogEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(models)
    }
}

public enum ModelCatalogSource: String, Sendable {
    case bundledVerified = "bundled-verified"
    case bundledUnverified = "bundled-unverified"
    case remote
    case cache
}

public enum ModelCatalogIssueContext: String, Sendable, Equatable {
    case remote
    case cache
    case bundled
}

public struct ModelCatalogLoadIssue: Sendable, Equatable {
    public let context: ModelCatalogIssueContext
    public let message: String

    public init(context: ModelCatalogIssueContext, message: String) {
        self.context = context
        self.message = message
    }
}

public struct ModelCatalogLoadResult: Sendable {
    public let entries: [ModelCatalogEntry]
    public let source: ModelCatalogSource
    public let issues: [ModelCatalogLoadIssue]

    public init(
        entries: [ModelCatalogEntry],
        source: ModelCatalogSource,
        issues: [ModelCatalogLoadIssue] = []
    ) {
        self.entries = entries
        self.source = source
        self.issues = issues
    }
}

public final class ModelCatalogService: @unchecked Sendable {
    public static let defaultRemoteManifestURL = URL(string: "https://models.waffle.app/v1/manifest.json")!

    private let manifestDataLoader: @Sendable () throws -> Data
    private let fileManager: FileManager
    private let applicationSupportDirectory: URL
    private let remoteManifestURL: URL
    private let session: URLSession
    private let manifestVerifier: ManifestVerifier

    public init(
        manifestDataLoader: (@Sendable () throws -> Data)? = nil,
        applicationSupportDirectory: URL? = nil,
        remoteManifestURL: URL = ModelCatalogService.defaultRemoteManifestURL,
        session: URLSession = .shared,
        manifestVerifier: ManifestVerifier = ManifestVerifier(),
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
        self.remoteManifestURL = remoteManifestURL
        self.session = session
        self.manifestVerifier = manifestVerifier
    }

    public func loadCatalog() throws -> [ModelCatalogEntry] {
        try loadBundledManifest().entries
    }

    public func loadBundledCatalogResult() -> ModelCatalogLoadResult {
        do {
            let bundled = try loadBundledManifest()
            return ModelCatalogLoadResult(
                entries: bundled.entries,
                source: bundled.source,
                issues: bundled.issues
            )
        } catch {
            return ModelCatalogLoadResult(
                entries: [],
                source: .bundledVerified,
                issues: [ModelCatalogLoadIssue(context: .bundled, message: describe(error: error))]
            )
        }
    }

    public func fetchRemoteManifest() async throws -> [ModelCatalogEntry] {
        do {
            let remote = try await fetchRemoteSignedManifest()
            let bundled = try? loadBundledManifest()

            if shouldPreferRemote(remoteManifest: remote.manifest, bundledManifest: bundled?.signedManifest)
                || bundled == nil
            {
                try? cacheManifestData(remote.data)
                return remote.manifest.models
            }

            return bundled?.entries ?? remote.manifest.models
        } catch let error as URLError {
            _ = error
            return try loadCatalog()
        }
    }

    public func loadCatalogWithRemoteFallback() async -> [ModelCatalogEntry] {
        await loadCatalogWithRemoteFallbackResult().entries
    }

    public func loadCatalogWithRemoteFallbackResult() async -> ModelCatalogLoadResult {
        let bundled = try? loadBundledManifest()
        var issues = bundled?.issues ?? []

        do {
            let remote = try await fetchRemoteSignedManifest()
            if shouldPreferRemote(remoteManifest: remote.manifest, bundledManifest: bundled?.signedManifest)
                || bundled == nil
            {
                try? cacheManifestData(remote.data)
                print("[ModelCatalog] Using remote manifest")
                return ModelCatalogLoadResult(entries: remote.manifest.models, source: .remote, issues: issues)
            }
        } catch {
            print("[ModelCatalog] Remote manifest unavailable: \(error)")
            issues.append(ModelCatalogLoadIssue(context: .remote, message: describe(error: error)))
        }

        do {
            let cached = try loadCachedManifest()
            if shouldPreferRemote(remoteManifest: cached.manifest, bundledManifest: bundled?.signedManifest)
                || bundled == nil
            {
                print("[ModelCatalog] Using cached manifest")
                return ModelCatalogLoadResult(entries: cached.manifest.models, source: .cache, issues: issues)
            }
        } catch {
            issues.append(ModelCatalogLoadIssue(context: .cache, message: describe(error: error)))
        }

        if let bundled {
            print("[ModelCatalog] Using bundled manifest")
            return ModelCatalogLoadResult(entries: bundled.entries, source: bundled.source, issues: issues)
        }

        return ModelCatalogLoadResult(entries: [], source: .bundledVerified, issues: issues)
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
            .appending(path: "Waffle", directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
        ensureDirectoryExists(at: url)
        return url
    }

    public func downloadsDirectoryURL() -> URL {
        let url = applicationSupportDirectory
            .appending(path: "Waffle", directoryHint: .isDirectory)
            .appending(path: "Downloads", directoryHint: .isDirectory)
        ensureDirectoryExists(at: url)
        return url
    }

    public func manifestCacheURL() -> URL {
        let waffleDirectory = applicationSupportDirectory
            .appending(path: "Waffle", directoryHint: .isDirectory)
        ensureDirectoryExists(at: waffleDirectory)
        return waffleDirectory.appending(path: "manifest-cache.json")
    }

    private func ensureDirectoryExists(at url: URL) {
        if fileManager.fileExists(atPath: url.path) == false {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func loadBundledManifest() throws -> ParsedManifest {
        let data = try manifestDataLoader()

        if let signed = try? JSONDecoder().decode(SignedModelManifest.self, from: data) {
            guard signed.manifestVersion == 2 else {
                throw ManifestVerificationError.unsupportedVersion
            }
            do {
                _ = try manifestVerifier.verify(manifest: signed)
                return ParsedManifest(
                    entries: signed.models,
                    signedManifest: signed,
                    source: .bundledVerified,
                    issues: []
                )
            } catch {
                // Bundled manifests are trusted fallbacks even when signature verification fails.
                return ParsedManifest(
                    entries: signed.models,
                    signedManifest: signed,
                    source: .bundledUnverified,
                    issues: [ModelCatalogLoadIssue(context: .bundled, message: describe(error: error))]
                )
            }
        }

        do {
            let models = try JSONDecoder().decode([ModelCatalogEntry].self, from: data)
            return ParsedManifest(
                entries: models,
                signedManifest: nil,
                source: .bundledVerified,
                issues: []
            )
        } catch {
            throw ManifestVerificationError.malformedManifest
        }
    }

    private func fetchRemoteSignedManifest() async throws -> ParsedSignedManifest {
        let (data, response) = try await session.data(from: remoteManifestURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let manifest = try parseSignedManifest(data: data)
        return ParsedSignedManifest(manifest: manifest, data: data)
    }

    private func loadCachedManifest() throws -> ParsedSignedManifest {
        let data = try Data(contentsOf: manifestCacheURL())
        let manifest = try parseSignedManifest(data: data)
        return ParsedSignedManifest(manifest: manifest, data: data)
    }

    private func cacheManifestData(_ data: Data) throws {
        try data.write(to: manifestCacheURL(), options: .atomic)
    }

    private func parseSignedManifest(data: Data) throws -> SignedModelManifest {
        guard let manifest = try? JSONDecoder().decode(SignedModelManifest.self, from: data) else {
            throw ManifestVerificationError.malformedManifest
        }
        guard manifest.manifestVersion == 2 else {
            throw ManifestVerificationError.unsupportedVersion
        }
        _ = try manifestVerifier.verify(manifest: manifest)
        return manifest
    }

    private func shouldPreferRemote(
        remoteManifest: SignedModelManifest,
        bundledManifest: SignedModelManifest?
    ) -> Bool {
        guard let bundledManifest else {
            return true
        }
        guard let remoteDate = parseISO8601(remoteManifest.signedAt) else {
            return false
        }
        guard let bundledDate = parseISO8601(bundledManifest.signedAt) else {
            return true
        }
        return remoteDate > bundledDate
    }

    private func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let withFractional = fractionalFormatter.date(from: value) {
            return withFractional
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func describe(error: Error) -> String {
        if let verificationError = error as? ManifestVerificationError {
            switch verificationError {
            case .invalidSignature:
                return "Manifest signature verification failed."
            case .unsupportedVersion:
                return "Manifest version is not supported."
            case .malformedManifest:
                return "Manifest data is malformed."
            }
        }

        if let urlError = error as? URLError {
            return "Network request failed: \(urlError.localizedDescription)"
        }

        return error.localizedDescription
    }
}

private func defaultApplicationSupportDirectory(fileManager: FileManager) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
}

private struct ParsedManifest {
    let entries: [ModelCatalogEntry]
    let signedManifest: SignedModelManifest?
    let source: ModelCatalogSource
    let issues: [ModelCatalogLoadIssue]
}

private struct ParsedSignedManifest {
    let manifest: SignedModelManifest
    let data: Data
}

private extension String {
    func hexDecodedData() -> Data? {
        guard count.isMultiple(of: 2) else {
            return nil
        }

        var data = Data(capacity: count / 2)
        var index = startIndex

        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: 2)
            let byteString = self[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
