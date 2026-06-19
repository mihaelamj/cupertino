import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
@testable import SearchToolProvider
import SharedConstants
import SQLite3
import Testing

// MARK: - #1284 — URI canonicalization cross-stage golden test

///
/// Per-stage URI normalization is well unit-tested (`Issue673URLUtilitiesFuzzTests`,
/// SharedModels tests), but the CROSS-stage invariant was not: that N casing /
/// dash-underscore variants of ONE logical Apple-docs URL collapse to a SINGLE
/// canonical URI at every stage (crawl-enqueue dedup, index storage, read
/// lookup) and that a read with any variant resolves to the one indexed
/// document.
///
/// This golden test feeds the production seams the variants directly:
///   - crawl stage: `Shared.Models.URLUtilities.normalize` (the enqueue dedup
///     key after #1284) — all variants collapse to one normalized URL.
///   - index/read stage: `appleDocsURI` / `CompositeToolProvider.normalizeReadDocumentURI`
///     (the same canonicalizer the indexer stores under and the `read_document`
///     handler looks up by) — all variants collapse to one `apple-docs://` URI.
///   - read resolution: a minimal `docs_metadata` row is indexed under the
///     canonical URI; `Search.Index.getDocumentContent` resolves it for EVERY
///     variant's normalized lookup.
@Suite("#1284 — one logical URL collapses to one URI across crawl/index/read")
struct Issue1284URICrossStageGoldenTests {
    /// Four web-form variants of ONE logical Apple doc, differing only in the
    /// depth-3 member component's casing and dash/underscore. #588 normalizes
    /// depth >= 3 by lowercasing and collapsing `_` -> `-`, so all four are the
    /// same logical URL.
    private static let variants: [String] = [
        "https://developer.apple.com/documentation/uikit/uiviewcontroller/view-did-load",
        "https://developer.apple.com/documentation/uikit/uiviewcontroller/view_did_load",
        "https://developer.apple.com/documentation/uikit/uiviewcontroller/View-Did-Load",
        "https://developer.apple.com/documentation/uikit/uiviewcontroller/VIEW_DID_LOAD",
    ]

    @Test("crawl-enqueue dedup key: all variants collapse to one normalized URL")
    func crawlEnqueueKeyCollapses() {
        let keys = Set(Self.variants.compactMap { raw -> String? in
            guard let url = URL(string: raw) else { return nil }
            return Shared.Models.URLUtilities.normalize(url)?.absoluteString
        })
        #expect(keys.count == 1, "crawl enqueue keys did not collapse: \(keys)")
    }

    @Test("index/read canonicalizer: all variants collapse to one apple-docs:// URI")
    func readCanonicalizerCollapses() {
        let uris = Set(Self.variants.map { CompositeToolProvider.normalizeReadDocumentURI($0) })
        #expect(uris.count == 1, "read canonicalizer did not collapse: \(uris)")
        // The read-stage canonical form equals the index-stage form: both go
        // through `appleDocsURI`, so the indexer stores exactly what the read
        // path looks up.
        let indexForm = URL(string: Self.variants[0]).flatMap(Shared.Models.URLUtilities.appleDocsURI(from:))
        #expect(uris.first == indexForm)
        #expect(uris.first?.hasPrefix("apple-docs://") == true)
    }

    @Test("end-to-end: one indexed URI, and a read with ANY variant resolves to it")
    func indexedOnceAndResolvesForEveryVariant() async throws {
        // The single indexed URI = the canonical form of the logical URL.
        let canonical = CompositeToolProvider.normalizeReadDocumentURI(Self.variants[0])

        let dbURL = try Self.makeMinimalDocsDB(uri: canonical)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let index = try await Search.Index(
            dbPath: dbURL,
            logger: Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty,
            readOnly: true
        )
        defer { Task { await index.disconnect() } }

        for variant in Self.variants {
            let lookup = CompositeToolProvider.normalizeReadDocumentURI(variant)
            #expect(lookup == canonical, "variant \(variant) did not normalize to the indexed URI")
            let content = try await index.getDocumentContent(uri: lookup, format: .json)
            #expect(content != nil, "read of variant \(variant) (lookup \(lookup)) did not resolve")
        }
    }

    /// A minimal schema-18 docs DB with one `docs_metadata` row at `uri`. Only
    /// the columns `getDocumentContent` reads are present; this is the read
    /// seam's hermetic fixture, not a full indexer build.
    private static func makeMinimalDocsDB(uri: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uri-1284-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("apple-documentation.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        let escaped = uri.replacingOccurrences(of: "'", with: "''")
        let sql = """
        CREATE TABLE docs_metadata (uri TEXT PRIMARY KEY, json_data TEXT NOT NULL);
        INSERT INTO docs_metadata (uri, json_data) VALUES ('\(escaped)', '{"rawMarkdown":"# UIViewController"}');
        PRAGMA user_version = \(Search.Index.schemaVersion);
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_close(db)
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }
        return dbURL
    }
}
