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

    // MARK: - Pin 1: each source's row roundtrips in its own destination DB

    @Test("Each Search.Index-owned source-id roundtrips through a hermetic per-source DB")
    func perSourceHermeticRoundtrip() async throws {
        // Round-16 critic finding #6: skip apple-sample-code from the
        // Search.Index sweep. In production its destination
        // (`apple-sample-code.db`) is owned by Sample.Index.Database
        // (sample-code projects / files / fingerprints schema), not
        // Search.Index's docs_metadata/docs_fts. The Sample.Index
        // pipeline's roundtrip is covered by
        // `Issue1037OneDBIntegrationTests`; including apple-sample-code
        // in THIS sweep would have indexed a docs-style row tagged
        // with `apple-sample-code` into a fake Search.Index DB,
        // oversells what the pin asserts.
        for sourceID in searchIndexOwnedSourceIDs {
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

    @Test("Two-way cross-destination isolation: A's row only in A's DB, B's row only in B's DB")
    func crossDestinationIsolation() async throws {
        let (aIndex, aPath) = try await makeFreshDB(tag: "iso-a")
        defer { try? FileManager.default.removeItem(at: aPath) }
        let (bIndex, bPath) = try await makeFreshDB(tag: "iso-b")
        defer { try? FileManager.default.removeItem(at: bPath) }

        // Round-16 critic finding #4: pre-fix B was never written to,
        // so any query against B returned [] and the negative
        // assertion was trivially satisfied. Now both DBs carry a
        // unique row; the test asserts BOTH directions of isolation.
        let titleA = "CrossDBIsolationProbeA_\(UUID().uuidString.prefix(8))"
        let titleB = "CrossDBIsolationProbeB_\(UUID().uuidString.prefix(8))"
        try await aIndex.indexDocument(Search.IndexDocumentParams(
            uri: "apple-docs://iso/a",
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: "Iso",
            title: titleA,
            content: "Should only exist in A.",
            filePath: "/tmp/iso-a",
            contentHash: "iso-a",
            lastCrawled: Date()
        ))
        try await bIndex.indexDocument(Search.IndexDocumentParams(
            uri: "hig://iso/b",
            source: Shared.Constants.SourcePrefix.hig,
            framework: "Iso",
            title: titleB,
            content: "Should only exist in B.",
            filePath: "/tmp/iso-b",
            contentHash: "iso-b",
            lastCrawled: Date()
        ))
        await aIndex.disconnect()
        await bIndex.disconnect()

        let reopenA = try await Search.Index(
            dbPath: aPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let aRowsForA = try await reopenA.search(query: titleA, includeArchive: true)
        let aRowsForB = try await reopenA.search(query: titleB, includeArchive: true)
        await reopenA.disconnect()

        let reopenB = try await Search.Index(
            dbPath: bPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        let bRowsForA = try await reopenB.search(query: titleA, includeArchive: true)
        let bRowsForB = try await reopenB.search(query: titleB, includeArchive: true)
        await reopenB.disconnect()

        // A's DB contains A's row, NOT B's.
        #expect(aRowsForA.count == 1, "A's DB must contain A's row")
        #expect(aRowsForA.first?.source == Shared.Constants.SourcePrefix.appleDocs)
        #expect(aRowsForB.isEmpty, "A's DB must NOT contain B's row (cross-DB leak)")

        // B's DB contains B's row, NOT A's.
        #expect(bRowsForB.count == 1, "B's DB must contain B's row")
        #expect(bRowsForB.first?.source == Shared.Constants.SourcePrefix.hig)
        #expect(bRowsForA.isEmpty, "B's DB must NOT contain A's row (cross-DB leak)")
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

    // MARK: - Pin 4: Search.Index destinations agree on PRAGMA user_version

    /// Source-ids whose destination DB is owned by Search.Index
    /// (file-level PRAGMA user_version is the schema stamp). Excludes
    /// `apple-sample-code` because its destination is shared with
    /// Sample.Index.Database, whose schema lives in a regular table
    /// (`samples_schema_version` per #1037 part 5), NOT PRAGMA
    /// user_version. The Sample.Index probe path is pinned by
    /// `SamplesSchemaVersionProbeTests`.
    private var searchIndexOwnedSourceIDs: [String] {
        CLIImpl.makeProductionSourceRegistry().allEnabled
            .filter { $0.destinationDB != .packages && $0.destinationDB != .appleSampleCode }
            .map(\.definition.id)
    }

    @Test("Search.Index-owned per-source DBs all stamp the same PRAGMA user_version (the current schema version)")
    func searchIndexDBsShareUserVersion() async throws {
        var observations: [(sourceID: String, version: Int32?)] = []
        for sourceID in searchIndexOwnedSourceIDs {
            let (index, dbPath) = try await makeFreshDB(tag: "schema-\(sourceID)")
            defer { try? FileManager.default.removeItem(at: dbPath) }
            await index.disconnect()
            observations.append((sourceID, Diagnostics.Probes.userVersion(at: dbPath)))
        }
        // Round-16 critic findings #1 + #2: assert one stamp per
        // source (no silent-skip on nil), AND assert the value
        // matches the canonical schema version (not just that the
        // values agree, which would pass for the all-zero pre-stamp
        // failure mode).
        for (sourceID, version) in observations {
            #expect(version != nil, "\(sourceID): PRAGMA user_version probe returned nil")
            #expect(version == Search.Index.schemaVersion, "\(sourceID) stamped at \(version ?? -1); expected \(Search.Index.schemaVersion)")
        }
    }
}
