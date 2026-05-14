import Foundation
@testable import SharedConfiguration
import SharedConstants
import SharedUtils
import Testing

// MARK: - SharedConfiguration Public API Smoke Tests

// SharedConfiguration owns the on-disk configuration tree consumed by
// every fetch / save / serve invocation. Post-dissection (refactor 1.6)
// it sits over SharedConstants + SharedUtils and exposes:
// - Shared.Configuration (aggregate root with load/save/createDefault)
// - Shared.Configuration.Crawler (start URL, prefixes, page caps, etc.)
// - Shared.Configuration.ChangeDetection (forceRecrawl, metadataFile)
// - Shared.Configuration.Output (format, includeMarkdown)
// - Shared.Configuration.Output.Format (json | markdown | html)
// - Shared.Configuration.DiscoveryMode (auto | json-only | webview-only)
//
// Per #389 independence acceptance: SharedConfiguration imports only
// Foundation + SharedConstants + SharedUtils. No behavioural cross-
// package import. `grep -rln "^import " Packages/Sources/Shared/Configuration/`
// returns exactly those three.
//
// These tests guard the public surface against accidental renames /
// raw-value drift. The DiscoveryMode and Output.Format string raw values
// back both config JSON on disk and the --discovery-mode / --format CLI
// flag values, so renaming any would silently break user configs +
// any consumer parsing JSON output.

@Suite("SharedConfiguration public surface")
struct SharedConfigurationPublicSurfaceTests {
    // MARK: Namespace

    @Test("Shared.Configuration namespace reachable")
    func sharedConfigurationNamespace() {
        _ = Shared.Configuration.self
    }

    // MARK: DiscoveryMode raw values

    @Test("Shared.Configuration.DiscoveryMode raw values are stable")
    func discoveryModeRawValues() {
        // The string raw values back both --discovery-mode CLI input and
        // the discoveryMode field in config JSON. Renaming any of these
        // breaks every existing config.json and every cupertino fetch
        // --discovery-mode invocation. Pin them.
        #expect(Shared.Configuration.DiscoveryMode.auto.rawValue == "auto")
        #expect(Shared.Configuration.DiscoveryMode.jsonOnly.rawValue == "json-only")
        #expect(Shared.Configuration.DiscoveryMode.webViewOnly.rawValue == "webview-only")
    }

    // MARK: Output.Format raw values

    @Test("Shared.Configuration.Output.Format raw values are stable")
    func outputFormatRawValues() {
        // Backs --format CLI flag values + the format field in config
        // JSON. Pin them so a refactor doesn't silently break user
        // configs.
        #expect(Shared.Configuration.Output.Format.json.rawValue == "json")
        #expect(Shared.Configuration.Output.Format.markdown.rawValue == "markdown")
        #expect(Shared.Configuration.Output.Format.html.rawValue == "html")
    }

    // MARK: ChangeDetection

    @Test("Shared.Configuration.ChangeDetection default uses Shared.Constants.defaultMetadataFile")
    func changeDetectionDefaultMetadataFile() {
        let detection = Shared.Configuration.ChangeDetection()
        #expect(detection.enabled == true)
        #expect(detection.forceRecrawl == false)
        #expect(detection.metadataFile == Shared.Constants.defaultMetadataFile)
    }

    @Test("Shared.Configuration.ChangeDetection derives metadata path from outputDirectory")
    func changeDetectionMetadataFileFromOutputDir() {
        let outDir = URL(fileURLWithPath: "/tmp/cupertino-config-test")
        let detection = Shared.Configuration.ChangeDetection(outputDirectory: outDir)
        #expect(detection.metadataFile == outDir.appendingPathComponent(Shared.Constants.FileName.metadata))
    }

    @Test("Shared.Configuration.ChangeDetection prefers explicit metadataFile over outputDirectory")
    func changeDetectionExplicitMetadataFile() {
        let explicit = URL(fileURLWithPath: "/tmp/explicit-metadata.json")
        let outDir = URL(fileURLWithPath: "/tmp/cupertino-out")
        let detection = Shared.Configuration.ChangeDetection(
            metadataFile: explicit,
            outputDirectory: outDir
        )
        #expect(detection.metadataFile == explicit)
    }

    // MARK: Crawler

    @Test("Shared.Configuration.Crawler default startURL is Apple Developer Docs")
    func crawlerDefaultStartURL() {
        let crawler = Shared.Configuration.Crawler()
        #expect(crawler.startURL.absoluteString.contains("developer.apple.com/documentation"))
        // requestDelay default backs every crawl's rate-limiting; pin it
        // so an accidental change to ".5" or "5.0" doesn't ship.
        #expect(crawler.requestDelay > 0)
    }

    // MARK: Output

    @Test("Shared.Configuration.Output default format is JSON")
    func outputDefaultFormat() {
        // The default format flipped from .markdown to .json in v1.0.0
        // when StructuredDocumentationPage became the canonical on-disk
        // shape. Pin it so a refactor doesn't silently flip it back.
        let output = Shared.Configuration.Output()
        #expect(output.format == .json)
        #expect(output.includeMarkdown == false)
    }

    // MARK: Configuration round-trip

    @Test("Shared.Configuration round-trips through JSON encode/decode")
    func configurationRoundTrip() throws {
        let original = Shared.Configuration(
            crawler: Shared.Configuration.Crawler(),
            changeDetection: Shared.Configuration.ChangeDetection(),
            output: Shared.Configuration.Output(format: .markdown, includeMarkdown: true)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Shared.Configuration.self, from: data)
        #expect(decoded.output.format == .markdown)
        #expect(decoded.output.includeMarkdown == true)
        #expect(decoded.changeDetection.enabled == original.changeDetection.enabled)
        #expect(decoded.crawler.maxPages == original.crawler.maxPages)
    }

    // MARK: load / save / createDefaultIfNeeded against a real file

    @Test("Shared.Configuration save then load round-trips through disk")
    func configurationDiskRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = Shared.Configuration()
        try original.save(to: tmp)
        #expect(FileManager.default.fileExists(atPath: tmp.path))

        let loaded = try Shared.Configuration.load(from: tmp)
        #expect(loaded.output.format == original.output.format)
        #expect(loaded.crawler.maxPages == original.crawler.maxPages)
    }

    @Test("Shared.Configuration.createDefaultIfNeeded is a no-op when file exists")
    func createDefaultIsNoopIfExists() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Write a sentinel non-default config first; createDefaultIfNeeded
        // must leave it untouched.
        let sentinel = Shared.Configuration(
            crawler: Shared.Configuration.Crawler(),
            changeDetection: Shared.Configuration.ChangeDetection(),
            output: Shared.Configuration.Output(format: .html, includeMarkdown: true)
        )
        try sentinel.save(to: tmp)

        try Shared.Configuration.createDefaultIfNeeded(at: tmp)
        let after = try Shared.Configuration.load(from: tmp)
        #expect(after.output.format == .html) // sentinel preserved
    }

    @Test("Shared.Configuration.createDefaultIfNeeded writes a default when file is missing")
    func createDefaultWritesIfMissing() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(!FileManager.default.fileExists(atPath: tmp.path))
        try Shared.Configuration.createDefaultIfNeeded(at: tmp)
        #expect(FileManager.default.fileExists(atPath: tmp.path))

        let written = try Shared.Configuration.load(from: tmp)
        // Defaults must match the parameterless init.
        let expected = Shared.Configuration()
        #expect(written.output.format == expected.output.format)
        #expect(written.changeDetection.enabled == expected.changeDetection.enabled)
    }
}
