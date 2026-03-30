import Foundation
import Testing

@Suite(.serialized)
struct ReleaseScriptsTests {
    @Test func buildReleaseValidateConfigRejectsPlaceholderSparkleKey() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let infoPlist = tempDirectory.appending(path: "Info.plist")
        try writeInfoPlist(
            to: infoPlist,
            feedURL: "https://updates.waffle.app/appcast.xml",
            publicKey: "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"
        )

        let result = try runScript(
            "scripts/build-release.sh",
            arguments: ["--validate-config"],
            environment: [
                "INFO_PLIST_PATH_OVERRIDE": infoPlist.path(),
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("SUPublicEDKey must be set"))
    }

    @Test func buildReleaseValidateConfigAcceptsExplicitFeedAndPublicKey() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let infoPlist = tempDirectory.appending(path: "Info.plist")
        try writeInfoPlist(
            to: infoPlist,
            feedURL: "https://updates.waffle.app/appcast.xml",
            publicKey: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/"
        )

        let result = try runScript(
            "scripts/build-release.sh",
            arguments: ["--validate-config"],
            environment: [
                "INFO_PLIST_PATH_OVERRIDE": infoPlist.path(),
            ]
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("configuration validation passed"))
    }

    @Test func buildReleaseValidateConfigRejectsNonHTTPSFeedURL() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let infoPlist = tempDirectory.appending(path: "Info.plist")
        try writeInfoPlist(
            to: infoPlist,
            feedURL: "http://localhost:8080/appcast.xml",
            publicKey: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/"
        )

        let result = try runScript(
            "scripts/build-release.sh",
            arguments: ["--validate-config"],
            environment: [
                "INFO_PLIST_PATH_OVERRIDE": infoPlist.path(),
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("SUFeedURL must be an https URL"))
    }

    @Test func generateAppcastProducesDeterministicOutput() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let outputPath = tempDirectory.appending(path: "appcast.xml")
        let result = try runScript(
            "scripts/generate-appcast.sh",
            environment: [
                "APPCAST_VERSION": "102",
                "APPCAST_SHORT_VERSION": "1.2.0",
                "APPCAST_DMG_URL": "https://github.com/andre/screamer/releases/download/v1.2.0/Waffle-1.2.0.dmg",
                "APPCAST_ED_SIGNATURE": "abc123signature==",
                "APPCAST_ARCHIVE_LENGTH": "4242",
                "APPCAST_MINIMUM_SYSTEM_VERSION": "14.0",
                "APPCAST_PUB_DATE": "Mon, 30 Mar 2026 18:00:00 +0000",
                "APPCAST_OUTPUT_PATH": outputPath.path(),
            ]
        )

        #expect(result.exitCode == 0)
        let xml = try String(contentsOf: outputPath, encoding: .utf8)
        let expected = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Waffle Updates</title>
    <item>
      <title>Version 1.2.0</title>
      <sparkle:version>102</sparkle:version>
      <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>Mon, 30 Mar 2026 18:00:00 +0000</pubDate>
      <enclosure
        url="https://github.com/andre/screamer/releases/download/v1.2.0/Waffle-1.2.0.dmg"
        sparkle:edSignature="abc123signature=="
        length="4242"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
        #expect(xml.trimmingCharacters(in: .whitespacesAndNewlines) == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func generateAppcastRejectsMalformedURL() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let outputPath = tempDirectory.appending(path: "appcast.xml")
        let result = try runScript(
            "scripts/generate-appcast.sh",
            environment: [
                "APPCAST_VERSION": "102",
                "APPCAST_SHORT_VERSION": "1.2.0",
                "APPCAST_DMG_URL": "github.com/andre/screamer/releases/download/v1.2.0/Waffle-1.2.0.dmg",
                "APPCAST_ED_SIGNATURE": "abc123signature==",
                "APPCAST_ARCHIVE_LENGTH": "4242",
                "APPCAST_MINIMUM_SYSTEM_VERSION": "14.0",
                "APPCAST_PUB_DATE": "Mon, 30 Mar 2026 18:00:00 +0000",
                "APPCAST_OUTPUT_PATH": outputPath.path(),
            ]
        )

        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("APPCAST_DMG_URL must be an absolute http(s) URL"))
    }

    @Test func signUpdateCanGenerateAppcastFromSigningOutput() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let dmgPath = tempDirectory.appending(path: "Waffle-1.2.0.dmg")
        try Data("fake dmg payload".utf8).write(to: dmgPath)
        let privateKeyPath = tempDirectory.appending(path: "sparkle-private.pem")
        try Data("private-key".utf8).write(to: privateKeyPath)
        let outputPath = tempDirectory.appending(path: "appcast.xml")
        let fakeSignUpdatePath = tempDirectory.appending(path: "fake-sign-update.sh")
        try Data(
            """
            #!/bin/bash
            echo 'sparkle:edSignature="sign123==" length="0"'
            """.utf8
        ).write(to: fakeSignUpdatePath)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: fakeSignUpdatePath.path()
        )

        let result = try runScript(
            "scripts/sign-update.sh",
            environment: [
                "VERSION": "1.2.0",
                "SPARKLE_PRIVATE_KEY_PATH": privateKeyPath.path(),
                "SPARKLE_SIGN_UPDATE_BIN": fakeSignUpdatePath.path(),
                "DMG_PATH_OVERRIDE": dmgPath.path(),
                "GENERATE_APPCAST": "1",
                "APPCAST_VERSION": "102",
                "APPCAST_SHORT_VERSION": "1.2.0",
                "APPCAST_DMG_URL": "https://github.com/andre/screamer/releases/download/v1.2.0/Waffle-1.2.0.dmg",
                "APPCAST_MINIMUM_SYSTEM_VERSION": "14.0",
                "APPCAST_PUB_DATE": "Mon, 30 Mar 2026 18:00:00 +0000",
                "APPCAST_OUTPUT_PATH": outputPath.path(),
            ]
        )

        #expect(result.exitCode == 0)
        let xml = try String(contentsOf: outputPath, encoding: .utf8)
        #expect(xml.contains("sparkle:edSignature=\"sign123==\""))
        #expect(xml.contains("length=\"16\""))
    }
}

private struct ScriptResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func runScript(
    _ relativePath: String,
    arguments: [String] = [],
    environment: [String: String] = [:]
) throws -> ScriptResult {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let scriptPath = repositoryRootPath().appending(path: relativePath).path()

    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptPath] + arguments
    process.currentDirectoryURL = repositoryRootPath()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    var mergedEnvironment = ProcessInfo.processInfo.environment
    mergedEnvironment.merge(environment) { _, new in new }
    process.environment = mergedEnvironment

    try process.run()
    process.waitUntilExit()

    let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    return ScriptResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}

private func writeInfoPlist(to url: URL, feedURL: String, publicKey: String) throws {
    let content = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>SUFeedURL</key>
        <string>\(feedURL)</string>
        <key>SUPublicEDKey</key>
        <string>\(publicKey)</string>
    </dict>
    </plist>
    """
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func repositoryRootPath() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
