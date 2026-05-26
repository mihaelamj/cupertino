@testable import CLI
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import Services
import ServicesModels
import SharedConstants
import Testing

// MARK: - #1039 end-to-end hig.db roundtrip

//
// Acceptance criterion #3 from issue #1039: "New roundtrip test:
// write a row to hig.db via the indexer, then `cupertino read
// hig://...` returns it." This suite is the end-to-end pin that
// proves the per-source URI routing actually opens the right DB
// file + returns the row.
//
// Companion to `ServicesReadServiceURIRoutingTests` which pins the
// pure `resolveDocsDBURL` string helper. Without an end-to-end test,
// a future refactor that quietly bypasses the helper (e.g. opens the
// wrong DB inside `readFromDocs`) would not be caught by unit tests
// alone.

@Suite("#1039 end-to-end: cupertino read hig://... opens hig.db")
struct Issue1039ReadHigRoundtripTests {
    /// A minimal `PackageFileLookupStrategy` stub for ReadService's
    /// composition root. The test never exercises the packages path,
    /// so the stub returns nil unconditionally.
    private struct NoopPackageFileLookup: Services.ReadService.PackageFileLookupStrategy {
        func fileContent(dbURL: URL, owner: String, repo: String, relpath: String) async throws -> String? {
            nil
        }
    }

    @Test("Write a row to a temp hig.db; cupertino read hig://... returns it via the per-source URI routing")
    func higRoundtripThroughReadService() async throws {
        // 1. Build a hermetic temp hig.db with one fixture row tagged
        // `hig` so the per-source URI scheme routing has a target.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1039-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let higDBPath = tempDir.appendingPathComponent("hig.db")
        let writer = try await Search.Index(
            dbPath: higDBPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        try await writer.indexDocument(Search.IndexDocumentParams(
            uri: "hig://buttons/standard-button",
            source: Shared.Constants.SourcePrefix.hig,
            framework: "HIG",
            title: "Standard Button",
            content: "Standard buttons let people choose familiar, common actions.",
            filePath: "/tmp/issue-1039-hig",
            contentHash: "issue-1039-hig",
            lastCrawled: Date()
        ))
        await writer.disconnect()

        // 2. ReadService composition root: docsDBURLs map points
        // `hig` -> the temp hig.db. `searchDB` is a non-existent
        // path so any fallback would loudly fail; this proves the
        // routing genuinely picked hig.db.
        let docsDBURLs: [String: URL] = ["hig": higDBPath]
        let bogusSearchDB = tempDir.appendingPathComponent("nonexistent.db")
        let bogusSamplesDB = tempDir.appendingPathComponent("nonexistent-samples.db")
        let bogusPackagesDB = tempDir.appendingPathComponent("nonexistent-packages.db")

        let result = try await Services.ReadService.read(
            identifier: "hig://buttons/standard-button",
            explicit: nil,
            format: .markdown,
            searchDB: bogusSearchDB,
            samplesDB: bogusSamplesDB,
            packagesDB: bogusPackagesDB,
            searchDatabaseFactory: LiveSearchDatabaseFactory(),
            sampleDatabaseFactory: LiveSampleIndexDatabaseFactory(),
            packageFileLookup: NoopPackageFileLookup(),
            docsDBURLs: docsDBURLs
        )

        #expect(result.resolvedSource == .docs)
        #expect(result.content.contains("Standard Button") || result.content.contains("Standard buttons"))
    }

    @Test("Non-URI identifier with explicit source `hig` routes through ReadService.read to hig.db end-to-end")
    func nonURIWithExplicitSourceHigRoutesEndToEnd() async throws {
        // Round-17 critic finding #3: pre-fix `cupertino read foo
        // --source hig` (non-URI identifier with explicit source)
        // fell back to legacy searchDB. Post-fix the explicit
        // source-id is threaded into `resolveDocsDBURL` and routes
        // to hig.db. Round-18 critic finding #3 strengthened the
        // test to actually call `ReadService.read` (not just the
        // pure helper), so an end-to-end regression that breaks
        // the explicit-source path inside `readFromDocs` is
        // caught.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1039-explicit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let higDBPath = tempDir.appendingPathComponent("hig.db")
        let writer = try await Search.Index(
            dbPath: higDBPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        // The non-URI fixture uses a slug-style identifier. The
        // read path queries the `uri` column of docs_metadata, so
        // we store the slug AS the uri value; this exercises the
        // explicit-source-id-driven DB routing without depending
        // on URI scheme parsing.
        let nonURIIdentifier = "issue-1039-explicit-hig-slug"
        try await writer.indexDocument(Search.IndexDocumentParams(
            uri: nonURIIdentifier,
            source: Shared.Constants.SourcePrefix.hig,
            framework: "HIG",
            title: "Standard Button (explicit-source variant)",
            content: "Body content for the explicit-source end-to-end roundtrip.",
            filePath: "/tmp/issue-1039-explicit-hig",
            contentHash: "issue-1039-explicit-hig",
            lastCrawled: Date()
        ))
        await writer.disconnect()

        let bogusSearchDB = tempDir.appendingPathComponent("nonexistent.db")
        let bogusSamplesDB = tempDir.appendingPathComponent("nonexistent-samples.db")
        let bogusPackagesDB = tempDir.appendingPathComponent("nonexistent-packages.db")

        let result = try await Services.ReadService.read(
            identifier: nonURIIdentifier,
            explicit: .docs,
            format: .markdown,
            searchDB: bogusSearchDB,
            samplesDB: bogusSamplesDB,
            packagesDB: bogusPackagesDB,
            searchDatabaseFactory: LiveSearchDatabaseFactory(),
            sampleDatabaseFactory: LiveSampleIndexDatabaseFactory(),
            packageFileLookup: NoopPackageFileLookup(),
            docsDBURLs: ["hig": higDBPath],
            explicitDocsSourceID: "hig"
        )

        #expect(result.resolvedSource == .docs)
        #expect(result.content.contains("Standard Button") || result.content.contains("explicit-source"))
    }
}
