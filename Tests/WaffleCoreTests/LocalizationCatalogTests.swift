import Foundation
import Testing

struct LocalizationCatalogTests {
    @Test func localizableCatalogExists() throws {
        let path = repositoryRootPath()
            .appendingPathComponent("Sources/WaffleApp/Localizable.xcstrings")
            .path
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func everyStringHasEnglishGermanAndJapaneseTranslations() throws {
        let url = repositoryRootPath().appendingPathComponent("Sources/WaffleApp/Localizable.xcstrings")
        let data = try Data(contentsOf: url)

        let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(raw["strings"] as? [String: Any])
        #expect(strings.isEmpty == false)

        for (key, entryValue) in strings {
            let entry = try #require(entryValue as? [String: Any], "Missing entry for key \(key)")
            let localizations = try #require(
                entry["localizations"] as? [String: Any],
                "Missing localizations for key \(key)"
            )

            for locale in ["en", "de", "ja"] {
                let localeEntry = try #require(
                    localizations[locale] as? [String: Any],
                    "Missing \(locale) localization for key \(key)"
                )
                let stringUnit = try #require(
                    localeEntry["stringUnit"] as? [String: Any],
                    "Missing string unit for key \(key), locale \(locale)"
                )
                let value = try #require(
                    stringUnit["value"] as? String,
                    "Missing localized value for key \(key), locale \(locale)"
                )
                #expect(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            }
        }
    }
}

private func repositoryRootPath() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
