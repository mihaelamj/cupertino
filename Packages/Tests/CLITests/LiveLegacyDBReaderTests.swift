@testable import CLI
import Distribution
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import Testing

// MARK: - LiveLegacyDBReader integration tests (step 6c-ii-b)

//
// End-to-end SQLite round-trip: write a synthetic legacy DB via the
// real Search.Index machinery, then read it back through
// LiveLegacyDBReader and verify counts + row content.

@Suite("LiveLegacyDBReader: raw-SQLite read-back from a Search.Index-built fixture")
struct LiveLegacyDBReaderTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-legacy-reader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Build a synthetic legacy search.db by writing rows through a
    /// real Search.Index, then close it so the file is in a clean
    /// state for the read-only reader.
    private func makeFixtureDB(at path: URL, rows: [Distribution.PerSourceDBSplitMigrator.LegacyRow]) async throws {
        let index = try await Search.Index(
            dbPath: path,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        for row in rows {
            try await index.indexDocument(row)
        }
        await index.disconnect()
    }

    private func row(uri: String, source: String) -> Distribution.PerSourceDBSplitMigrator.LegacyRow {
        Distribution.PerSourceDBSplitMigrator.LegacyRow(
            uri: uri,
            source: source,
            framework: "FixtureFramework",
            title: "Title for \(uri)",
            content: "Content for \(uri).",
            filePath: "/tmp/\(uri)",
            contentHash: "hash-\(uri)",
            lastCrawled: Date(timeIntervalSince1970: 1700000000)
        )
    }

    @Test("sourceIDCounts returns the right [source-id: count] map")
    func sourceIDCountsRoundtrip() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("legacy.db")
        try await makeFixtureDB(at: dbPath, rows: [
            row(uri: "ad://1", source: "apple-docs"),
            row(uri: "ad://2", source: "apple-docs"),
            row(uri: "ad://3", source: "apple-docs"),
            row(uri: "h://1", source: "hig"),
        ])

        let reader = LiveLegacyDBReader(legacyFile: dbPath)
        let counts = try await reader.sourceIDCounts()
        #expect(counts.count == 2)
        #expect(counts["apple-docs"] == 3)
        #expect(counts["hig"] == 1)
    }

    @Test("rows(forSourceID:) streams only the rows for the requested source")
    func rowsForSourceIDIsFiltered() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("legacy.db")
        try await makeFixtureDB(at: dbPath, rows: [
            row(uri: "ad://1", source: "apple-docs"),
            row(uri: "ad://2", source: "apple-docs"),
            row(uri: "h://1", source: "hig"),
        ])

        let reader = LiveLegacyDBReader(legacyFile: dbPath)
        var appleDocsURIs: [String] = []
        for try await yielded in reader.rows(forSourceID: "apple-docs") {
            appleDocsURIs.append(yielded.uri)
        }
        #expect(Set(appleDocsURIs) == ["ad://1", "ad://2"])

        var higURIs: [String] = []
        for try await yielded in reader.rows(forSourceID: "hig") {
            higURIs.append(yielded.uri)
        }
        #expect(higURIs == ["h://1"])
    }

    @Test("rows(forSourceID:) preserves the full IndexDocumentParams round-trip (title + content + lastCrawled)")
    func rowsPreserveFullFidelity() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("legacy.db")
        let fixtureRow = row(uri: "ad://full-fidelity", source: "apple-docs")
        try await makeFixtureDB(at: dbPath, rows: [fixtureRow])

        let reader = LiveLegacyDBReader(legacyFile: dbPath)
        var collected: [Distribution.PerSourceDBSplitMigrator.LegacyRow] = []
        for try await yielded in reader.rows(forSourceID: "apple-docs") {
            collected.append(yielded)
        }
        #expect(collected.count == 1)
        let readBack = try #require(collected.first)
        #expect(readBack.uri == "ad://full-fidelity")
        #expect(readBack.source == "apple-docs")
        #expect(readBack.framework == "FixtureFramework")
        #expect(readBack.title == "Title for ad://full-fidelity")
        #expect(readBack.content == "Content for ad://full-fidelity.")
        #expect(readBack.filePath == "/tmp/ad://full-fidelity")
        #expect(readBack.contentHash == "hash-ad://full-fidelity")
        #expect(readBack.lastCrawled.timeIntervalSince1970 == 1700000000)
    }

    @Test("sourceIDCounts on a non-existent file throws LegacyReaderError.openFailed")
    func sourceIDCountsThrowsForMissingFile() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("does-not-exist.db")
        let reader = LiveLegacyDBReader(legacyFile: dbPath)
        await #expect(throws: LiveLegacyDBReader.LegacyReaderError.self) {
            _ = try await reader.sourceIDCounts()
        }
    }

    @Test("End-to-end migration through Live reader + Live writer + real Search.Index")
    func endToEndMigration() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyPath = dir.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        try await makeFixtureDB(at: legacyPath, rows: [
            row(uri: "ad://1", source: "apple-docs"),
            row(uri: "ad://2", source: "apple-docs"),
            row(uri: "h://1", source: "hig"),
        ])

        let registry = CLIImpl.makeProductionSourceRegistry()
        let reader = LiveLegacyDBReader(legacyFile: legacyPath)
        let writerFactory = LivePerDBWriterFactory.make(logger: LoggingModels.Logging.NoopRecording())

        let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
            legacyFile: legacyPath,
            baseDirectory: dir,
            registry: registry,
            reader: reader,
            writerFactory: writerFactory
        )

        #expect(outcome.totalRowsWritten == 3, "all 3 rows migrated")
        #expect(outcome.legacyFileRenamed == true)
        // Per-source DB files exist on disk.
        let appleDocPath = dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleDocumentation.filename)
        let higPath = dir.appendingPathComponent(Shared.Models.DatabaseDescriptor.hig.filename)
        #expect(FileManager.default.fileExists(atPath: appleDocPath.path))
        #expect(FileManager.default.fileExists(atPath: higPath.path))
        // Legacy file renamed.
        let renamed = dir.appendingPathComponent("search.db.legacy-pre-per-source-split")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(!FileManager.default.fileExists(atPath: legacyPath.path))
    }
}
