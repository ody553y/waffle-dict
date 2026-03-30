import CryptoKit
import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct ModelCatalogTests {
    @Test func loadCatalogDecodesFixtureEntries() throws {
        let service = try makeCatalogService()

        let entries = try service.loadCatalog()

        #expect(entries.count == 2)
        #expect(entries.first?.id == "whisper-small")
        #expect(entries.first?.family == .whisper)
        #expect(entries.first?.displayName == "Whisper Small")
        #expect(entries.first?.sizeMB == 488)
        #expect(entries.first?.supportsTranslation == true)
        #expect(entries.last?.available == false)
    }

    @Test func installedModelsReflectDirectoriesInModelsFolder() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let service = ModelCatalogService(
            manifestDataLoader: { Data("[]".utf8) },
            applicationSupportDirectory: tempDirectory
        )
        let installDirectory = service.installPath(for: "whisper-small")
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try Data("installed".utf8).write(to: installDirectory.appending(path: "model.bin"))

        let installedModels = service.installedModels()

        #expect(installedModels == ["whisper-small"])
        #expect(service.isInstalled(id: "whisper-small"))
        #expect(service.isInstalled(id: "whisper-medium") == false)
    }

    @Test func resolveSelectedModelPrefersInstalledSelectionThenDefaultThenFirstInstalled() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let service = ModelCatalogService(
            manifestDataLoader: { Data("[]".utf8) },
            applicationSupportDirectory: tempDirectory
        )

        try FileManager.default.createDirectory(
            at: service.installPath(for: "whisper-tiny"),
            withIntermediateDirectories: true
        )
        try Data("tiny".utf8).write(
            to: service.installPath(for: "whisper-tiny").appending(path: "model.bin")
        )
        try FileManager.default.createDirectory(
            at: service.installPath(for: "whisper-small"),
            withIntermediateDirectories: true
        )
        try Data("small".utf8).write(
            to: service.installPath(for: "whisper-small").appending(path: "model.bin")
        )

        #expect(service.resolveSelectedModelID(currentSelection: "whisper-tiny") == "whisper-tiny")
        #expect(service.resolveSelectedModelID(currentSelection: "whisper-medium") == "whisper-small")

        try FileManager.default.removeItem(at: service.installPath(for: "whisper-small"))

        #expect(service.resolveSelectedModelID(currentSelection: "whisper-medium") == "whisper-tiny")

        try FileManager.default.removeItem(at: service.installPath(for: "whisper-tiny"))

        #expect(service.resolveSelectedModelID(currentSelection: nil) == nil)
    }

    @Test func loadCatalogDecodesSignedManifestWhenSignatureIsValid() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyHex = privateKey.publicKey.rawRepresentation.hexEncodedString()
        let signedManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small"), makeCatalogEntry(id: "whisper-base")],
            signedAt: "2026-03-30T12:00:00Z",
            privateKey: privateKey
        )

        let service = ModelCatalogService(
            manifestDataLoader: { signedManifestData },
            manifestVerifier: ManifestVerifier(publicKeyHex: publicKeyHex)
        )

        let entries = try service.loadCatalog()

        #expect(entries.map(\.id) == ["whisper-small", "whisper-base"])
    }

    @Test func loadCatalogUsesBundledEntriesWhenSignatureIsInvalid() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyHex = privateKey.publicKey.rawRepresentation.hexEncodedString()
        let signedManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small")],
            signedAt: "2026-03-30T12:00:00Z",
            privateKey: privateKey
        )
        var payload = try #require(
            JSONSerialization.jsonObject(with: signedManifestData) as? [String: Any]
        )
        var models = try #require(payload["models"] as? [[String: Any]])
        models[0]["size_mb"] = 999
        payload["models"] = models
        let tamperedData = try JSONSerialization.data(withJSONObject: payload)

        let service = ModelCatalogService(
            manifestDataLoader: { tamperedData },
            manifestVerifier: ManifestVerifier(publicKeyHex: publicKeyHex)
        )

        let entries = try service.loadCatalog()
        #expect(entries.count == 1)
        #expect(entries.first?.id == "whisper-small")
    }

    @Test func signedManifestNormalizationMatchesCanonicalJSONString() throws {
        let models = [makeCatalogEntry(id: "whisper-small")]

        let normalizedData = try ManifestVerifier.normalizedModelsData(models)
        let normalizedString = try #require(String(data: normalizedData, encoding: .utf8))

        #expect(
            normalizedString
                == #"[{"available":true,"display_name":"Whisper Small","download_url":"https://models.waffle.app/v1/models/whisper-small.tar.gz","family":"whisper","id":"whisper-small","languages":["multilingual"],"sha256_checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size_mb":488,"supports_live":false,"supports_translation":true}]"#
        )
    }

    @Test func loadCatalogWithRemoteFallbackUsesNewerRemoteManifestAndCachesIt() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyHex = privateKey.publicKey.rawRepresentation.hexEncodedString()
        let bundledManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small")],
            signedAt: "2026-03-30T12:00:00Z",
            privateKey: privateKey
        )
        let remoteManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small"), makeCatalogEntry(id: "whisper-medium")],
            signedAt: "2026-03-30T12:30:00Z",
            privateKey: privateKey
        )
        let session = URLSession.makeManifestMockingSession(statusCode: 200, body: remoteManifestData)

        let service = ModelCatalogService(
            manifestDataLoader: { bundledManifestData },
            applicationSupportDirectory: tempDirectory,
            remoteManifestURL: URL(string: "https://models.waffle.app/v1/manifest.json")!,
            session: session,
            manifestVerifier: ManifestVerifier(publicKeyHex: publicKeyHex)
        )

        let entries = await service.loadCatalogWithRemoteFallback()

        #expect(entries.map(\.id) == ["whisper-small", "whisper-medium"])
        #expect(FileManager.default.fileExists(atPath: service.manifestCacheURL().path))
    }

    @Test func loadCatalogWithRemoteFallbackUsesCachedManifestWhenNetworkFails() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyHex = privateKey.publicKey.rawRepresentation.hexEncodedString()
        let bundledManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small")],
            signedAt: "2026-03-30T12:00:00Z",
            privateKey: privateKey
        )
        let cachedManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-large-v3")],
            signedAt: "2026-03-30T12:45:00Z",
            privateKey: privateKey
        )
        let session = URLSession.makeManifestMockingSession(error: URLError(.notConnectedToInternet))

        let service = ModelCatalogService(
            manifestDataLoader: { bundledManifestData },
            applicationSupportDirectory: tempDirectory,
            remoteManifestURL: URL(string: "https://models.waffle.app/v1/manifest.json")!,
            session: session,
            manifestVerifier: ManifestVerifier(publicKeyHex: publicKeyHex)
        )
        try cachedManifestData.write(to: service.manifestCacheURL())

        let entries = await service.loadCatalogWithRemoteFallback()

        #expect(entries.map(\.id) == ["whisper-large-v3"])
    }

    @Test func loadCatalogWithRemoteFallbackIgnoresRemoteManifestWhenBundledIsNewer() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyHex = privateKey.publicKey.rawRepresentation.hexEncodedString()
        let bundledManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small")],
            signedAt: "2026-03-30T13:00:00Z",
            privateKey: privateKey
        )
        let remoteManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-tiny")],
            signedAt: "2026-03-30T12:00:00Z",
            privateKey: privateKey
        )
        let session = URLSession.makeManifestMockingSession(statusCode: 200, body: remoteManifestData)

        let service = ModelCatalogService(
            manifestDataLoader: { bundledManifestData },
            applicationSupportDirectory: tempDirectory,
            remoteManifestURL: URL(string: "https://models.waffle.app/v1/manifest.json")!,
            session: session,
            manifestVerifier: ManifestVerifier(publicKeyHex: publicKeyHex)
        )

        let entries = await service.loadCatalogWithRemoteFallback()

        #expect(entries.map(\.id) == ["whisper-small"])
    }

    @Test func loadCatalogWithRemoteFallbackUsesBundledEntriesWhenBundledSignatureIsInvalidAndRemoteUnavailable()
        async throws
    {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyHex = privateKey.publicKey.rawRepresentation.hexEncodedString()
        let signedManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small"), makeCatalogEntry(id: "whisper-medium")],
            signedAt: "2026-03-30T13:00:00Z",
            privateKey: privateKey
        )
        var payload = try #require(
            JSONSerialization.jsonObject(with: signedManifestData) as? [String: Any]
        )
        payload["signature"] = String(repeating: "f", count: 128)
        let invalidBundledManifestData = try JSONSerialization.data(withJSONObject: payload)
        let session = URLSession.makeManifestMockingSession(error: URLError(.networkConnectionLost))

        let service = ModelCatalogService(
            manifestDataLoader: { invalidBundledManifestData },
            applicationSupportDirectory: tempDirectory,
            remoteManifestURL: URL(string: "https://models.waffle.app/v1/manifest.json")!,
            session: session,
            manifestVerifier: ManifestVerifier(publicKeyHex: publicKeyHex)
        )

        let result = await service.loadCatalogWithRemoteFallbackResult()

        #expect(result.entries.map(\.id) == ["whisper-small", "whisper-medium"])
        #expect(result.source == .bundledUnverified)
        #expect(result.issues.contains { $0.context == .bundled })
        #expect(result.issues.contains { $0.context == .remote })
    }

    @Test func loadCatalogWithRemoteFallbackRejectsCachedManifestWithInvalidSignature() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyHex = privateKey.publicKey.rawRepresentation.hexEncodedString()
        let bundledManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-small")],
            signedAt: "2026-03-30T13:00:00Z",
            privateKey: privateKey
        )
        let signedCachedManifestData = try makeSignedManifestData(
            models: [makeCatalogEntry(id: "whisper-medium")],
            signedAt: "2026-03-30T14:00:00Z",
            privateKey: privateKey
        )
        var cachedPayload = try #require(
            JSONSerialization.jsonObject(with: signedCachedManifestData) as? [String: Any]
        )
        cachedPayload["signature"] = String(repeating: "0", count: 128)
        let invalidCachedManifestData = try JSONSerialization.data(withJSONObject: cachedPayload)
        let session = URLSession.makeManifestMockingSession(error: URLError(.notConnectedToInternet))

        let service = ModelCatalogService(
            manifestDataLoader: { bundledManifestData },
            applicationSupportDirectory: tempDirectory,
            remoteManifestURL: URL(string: "https://models.waffle.app/v1/manifest.json")!,
            session: session,
            manifestVerifier: ManifestVerifier(publicKeyHex: publicKeyHex)
        )
        try invalidCachedManifestData.write(to: service.manifestCacheURL())

        let result = await service.loadCatalogWithRemoteFallbackResult()

        #expect(result.entries.map(\.id) == ["whisper-small"])
        #expect(result.source == .bundledVerified)
        #expect(result.issues.contains { $0.context == .cache })
    }
}

private func makeCatalogService() throws -> ModelCatalogService {
    let fixtureURL = try #require(Bundle.module.url(forResource: "test-models-manifest", withExtension: "json"))
    return ModelCatalogService(
        manifestDataLoader: {
            try Data(contentsOf: fixtureURL)
        }
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeCatalogEntry(id: String) -> ModelCatalogEntry {
    ModelCatalogEntry(
        id: id,
        family: .whisper,
        displayName: id.replacingOccurrences(of: "-", with: " ").capitalized,
        sizeMB: id == "whisper-small" ? 488 : 75,
        languages: ["multilingual"],
        supportsLive: false,
        supportsTranslation: true,
        downloadURL: URL(string: "https://models.waffle.app/v1/models/\(id).tar.gz")!,
        sha256Checksum: String(repeating: "a", count: 64),
        available: true
    )
}

private func makeSignedManifestData(
    models: [ModelCatalogEntry],
    signedAt: String,
    privateKey: Curve25519.Signing.PrivateKey
) throws -> Data {
    let normalizedModels = try ManifestVerifier.normalizedModelsData(models)
    let signature = try privateKey.signature(for: normalizedModels).hexEncodedString()
    let payload: [String: Any] = [
        "manifest_version": 2,
        "signed_at": signedAt,
        "signature": signature,
        "models": models.map { model in
            [
                "id": model.id,
                "family": model.family.rawValue,
                "display_name": model.displayName,
                "size_mb": model.sizeMB,
                "languages": model.languages,
                "supports_live": model.supportsLive,
                "supports_translation": model.supportsTranslation,
                "download_url": model.downloadURL.absoluteString,
                "sha256_checksum": model.sha256Checksum,
                "available": model.available,
            ] as [String: Any]
        },
    ]
    return try JSONSerialization.data(withJSONObject: payload)
}

private final class ManifestMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var error: Error?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://models.waffle.app/v1/manifest.json")!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func makeManifestMockingSession(statusCode: Int, body: Data) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManifestMockURLProtocol.self]
        ManifestMockURLProtocol.error = nil
        ManifestMockURLProtocol.statusCode = statusCode
        ManifestMockURLProtocol.body = body
        return URLSession(configuration: configuration)
    }

    static func makeManifestMockingSession(error: Error) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManifestMockURLProtocol.self]
        ManifestMockURLProtocol.error = error
        ManifestMockURLProtocol.body = Data()
        return URLSession(configuration: configuration)
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
