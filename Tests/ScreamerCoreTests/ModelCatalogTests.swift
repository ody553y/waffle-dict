import Foundation
import Testing
@testable import ScreamerCore

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
