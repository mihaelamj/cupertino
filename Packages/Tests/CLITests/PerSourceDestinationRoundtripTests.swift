@testable import CLI
import Diagnostics
import Foundation
import LoggingModels
import SearchAPI
import SearchModels
import SearchSQLite
import SharedConstants
import Testing

// MARK: - Per-source destination DB roundtrip

//
// Post-#1037/#1038 per-source DB split: each `SourceProvider`
// declares its own `destinationDB`, and each per-source DB lives
// in its own SQLite file on disk. This suite pins the load-bearing
// contract: a row tagged with source-id X, written to source X's
// destination DB, can be queried back from that destination DB
// (and NOT from a different source's destination DB).
//
// Companion to `Issue1033AllSourcesRoundtripTests` which pins
// the same write-read flow against a single shared DB (testing the
// `source` column roundtrip). This suite extends that to the
// post-#1037 per-source destination DB structure.

@Suite("Per-source destination DB write-read roundtrip (#1036 phase 7)")
struct PerSourceDestinationRoundtripTests {
    // MARK: - Helpers

    /// Open a fresh per-source DB at a unique temp path.
    private func makeFreshDB(tag: String) async throws -> (Search.Index, URL) {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("per-source-roundtrip-\(tag)-\(UUID().uuidString).db")
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        return (index, dbPath)
    }

    /// All search-bound source-ids derived from the production
    /// registry. Filters out `.packages` (which has its own
    /// pipeline, not Search.Index-based).
    private var searchBoundSourceIDs: [String] {
        CLIImpl.makeProductionSourceRegistry().allEnabled
            .filter { $0.destinationDB != .packages }
            .map(\.definition.id)
    }

    // MARK: - Pin 1: each source's row roundtrips in its own destination DB

    @Test("Each search-bound source-id roundtrips through a hermetic per-source DB")
    func perSourceHermeticRoundtrip() async throws {
        for sourceID in searchBoundSourceIDs {
            let (index, dbPath) = try await makeFreshDB(tag: sourceID)
            defer { try? FileManager.default.removeItem(at: dbPath) }

            let title = "PerSourceFixture_\(sourceID.replacingOccurrences(of: "-", with: "_"))"
            try await index.indexDocument(Search.IndexDocumentParams(
                uri: "\(sourceID)://per-source/fixture",
                source: sourceID,
                framework: "Fixture",
                title: title,
                content: "Per-source destination roundtrip body for \(sourceID).",
                filePath: "/tmp/per-source-\(sourceID)",
                contentHash: "per-source-\(sourceID)",
                lastCrawled: Date()
            ))
            await index.disconnect()

            let reopened = try await Search.Index(
                dbPath: dbPath,
                logger: LoggingModels.Logging.NoopRecording(),
                indexers: [:],
                sourceLookup: .empty
            )
            // includeArchive: true so apple-archive doesn't get
            // silently filtered (Search.Index.search default-false).
            let rows = try await reopened.search(query: title, includeArchive: true)
            await reopened.disconnect()

            #expect(rows.count == 1, "expected exactly one row for \(sourceID); got \(rows.count)")
            #expect(rows.first?.source == sourceID, "row in \(sourceID)'s DB must carry source-id \(sourceID); got \(rows.first?.source ?? "nil")")
        }
    }

    // MARK: - Pin 2: cross-DB isolation

    @Test("Row written to source A's destination DB does NOT leak into source B's destination DB")
    func crossDestinationIsolation() async throws {
        let (aIndex, aPath) = try await makeFreshDB(tag: "iso-a")
        defer { try? FileManager.default.removeItem(at: aPath) }
        let (bIndex, bPath) = try await makeFreshDB(tag: "iso-b")
        defer { try? FileManager.default.removeItem(at: bPath) }

        let uniqueTitle = "CrossDBIsolationProbe_\(UUID().uuidString.prefix(8))"
        try await aIndex.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://iso/a",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "Iso",
            title: uniqueTitle,
            content: "Should only exist in A.",
            filePath: "/tmp/iso-a",
            contentHash: "iso-a",
            lastCrawled: Date()
        ))
        await aIndex.disconnect()

        // Reopen A: row is there.
        let reopenA = try await Search.Index(
            dbPath: aPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let aRows = try await reopenA.search(query: uniqueTitle, includeArchive: true)
        await reopenA.disconnect()
        #expect(aRows.count == 1, "A's row must be readable from A's DB")
        #expect(aRows.first?.source == Shared.Constants.SourcePrefix.appleDocs)

        // B's DB is hermetic: A's row must NOT be there.
        let bRows = try await bIndex.search(query: uniqueTitle, includeArchive: true)
        await bIndex.disconnect()
        #expect(bRows.isEmpty, "A's row must NOT leak into B's DB (got \(bRows.count) rows)")
    }

    // MARK: - Pin 3: destination DB filenames are distinct

    @Test("Every search-bound destination has a unique filename (no two sources collide on disk)")
    func destinationFilenamesAreUnique() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let filenames = registry.allEnabled
            .filter { $0.destinationDB != .packages }
            .map(\.destinationDB.filename)
        // Post-#1038 swift-org and swift-book each own their own
        // descriptor, so 7 search-bound providers route to 7
        // distinct filenames (apple-documentation, hig,
        // apple-archive, swift-evolution, swift-org, swift-book,
        // apple-sample-code).
        let unique = Set(filenames)
        #expect(unique.count == filenames.count, "two sources collide on the same destination filename: \(filenames)")
    }

    // MARK: - Pin 4: schema versions match across per-source DBs

    @Test("All per-source destination DBs are stamped at the same schema version on creation")
    func perSourceDBsShareSchemaVersion() async throws {
        var stampedVersions: Set<Int32> = []
        for sourceID in searchBoundSourceIDs {
            let (index, dbPath) = try await makeFreshDB(tag: "schema-\(sourceID)")
            defer { try? FileManager.default.removeItem(at: dbPath) }
            await index.disconnect()
            // Diagnostics.Probes reads PRAGMA user_version. For
            // apple-sample-code the schema is in a regular table
            // (samples_schema_version per #1037 part 5), and that
            // probe path is separately tested by
            // SamplesSchemaVersionProbeTests; here we just verify
            // the Search.Index file-level stamp.
            if let version = Diagnostics.Probes.userVersion(at: dbPath) {
                stampedVersions.insert(version)
            }
        }
        #expect(stampedVersions.count == 1, "expected one shared schema version across per-source DBs; got \(stampedVersions)")
    }
}
