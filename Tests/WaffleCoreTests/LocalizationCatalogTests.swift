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
        let strings = try loadLocalizationEntries()
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

    @Test func everyReferencedLocalizedKeyExistsInLocalizationCatalog() throws {
        let catalogEntries = try loadLocalizationEntries()
        let catalogKeys = Set(catalogEntries.keys)
        let referencedKeys = try extractReferencedLocalizedKeys()

        #expect(referencedKeys.isEmpty == false)

        let missingKeys = referencedKeys.subtracting(catalogKeys).sorted()
        #expect(
            missingKeys.isEmpty,
            """
            Missing localization keys in Localizable.xcstrings:
            \(missingKeys.joined(separator: "\n"))
            """
        )
    }
}

private func loadLocalizationEntries() throws -> [String: Any] {
    let url = repositoryRootPath().appendingPathComponent("Sources/WaffleApp/Localizable.xcstrings")
    let data = try Data(contentsOf: url)
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(raw["strings"] as? [String: Any])
}

private func extractReferencedLocalizedKeys() throws -> Set<String> {
    let appSourceDirectory = repositoryRootPath().appendingPathComponent("Sources/WaffleApp")
    let swiftFiles = try swiftSourceFiles(under: appSourceDirectory)

    let pattern = #"\blocalized(?:Format)?\s*\(\s*"((?:\\.|[^"\\])+)""#
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    var keys = Set<String>()

    for file in swiftFiles {
        let source = try String(contentsOf: file, encoding: .utf8)
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, options: [], range: nsRange) {
            guard match.numberOfRanges > 1 else { continue }
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            keys.insert(String(source[range]))
        }
    }

    return keys
}

private func swiftSourceFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var files: [URL] = []
    for case let fileURL as URL in enumerator {
        guard fileURL.pathExtension == "swift" else { continue }
        files.append(fileURL)
    }
    return files.sorted { $0.path < $1.path }
}

private func repositoryRootPath() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
