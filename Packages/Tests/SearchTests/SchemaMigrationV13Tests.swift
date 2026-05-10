import Foundation
@testable import Search
import Shared
import SQLite3
import Testing

// MARK: - v13 URL case canonicalization migration (#283)

//
// Two suites:
// - Pure planner: drives `Search.Index.v13PlanRenames(from:)` against
//   synthetic `V13MetadataRow` inputs; no DB, no I/O. Covers the merge
//   semantics in isolation.
// - Integration: seeds a v12-shaped fixture DB with case-variant rows, opens
//   it via `Search.Index(dbPath:)` (which runs `checkAndMigrateSchema` and
//   triggers `migrateToVersion13`), then verifies the on-disk state with a
//   raw sqlite handle.

// MARK: - Fixture helpers

private func makeTempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("v13-migration-\(UUID().uuidString).db")
}

private enum FixtureError: Error {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
}

/// Open the DB at `dbPath` raw, run `block`, close. Used by tests to seed
/// synthetic rows or read back state without going through `Search.Index`.
private func withRawDB(at dbPath: URL, _ block: (OpaquePointer) throws -> Void) throws {
    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw FixtureError.openFailed(dbPath.path)
    }
    defer { sqlite3_close(db) }
    guard let db else { throw FixtureError.openFailed(dbPath.path) }
    try block(db)
}

private func exec(_ db: OpaquePointer, _ sql: String) throws {
    var err: UnsafeMutablePointer<CChar>?
    defer { sqlite3_free(err) }
    guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
        throw FixtureError.execFailed(err.map { String(cString: $0) } ?? "unknown")
    }
}

/// Insert one synthetic `docs_metadata` row with the four fields v13 cares
/// about, plus a stub `json_data` carrying the URL. Other columns get safe
/// defaults from the table schema.
private func insertMetadataRow(
    _ db: OpaquePointer,
    uri: String,
    framework: String,
    url: String,
    lastCrawled: Int64
) throws {
    let sql = """
    INSERT INTO docs_metadata
        (uri, source, framework, language, kind, file_path, content_hash, last_crawled, word_count, json_data)
    VALUES (?, 'apple-docs', ?, 'swift', 'unknown', '/tmp/seed', 'h', ?, 1, ?);
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw FixtureError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
    let json = #"{"url":"\#(url)"}"#
    sqlite3_bind_text(stmt, 1, uri, -1, transient)
    sqlite3_bind_text(stmt, 2, framework, -1, transient)
    sqlite3_bind_int64(stmt, 3, lastCrawled)
    sqlite3_bind_text(stmt, 4, json, -1, transient)
    guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw FixtureError.execFailed(String(cString: sqlite3_errmsg(db)))
    }
}

/// Mirror of the indexer's docs_fts insert. Just enough to verify FTS rows
/// follow URI updates / deletions through the migration.
private func insertFTSRow(_ db: OpaquePointer, uri: String, framework: String, title: String) throws {
    let sql = """
    INSERT INTO docs_fts (uri, source, framework, language, title, content, summary, symbols)
    VALUES (?, 'apple-docs', ?, 'swift', ?, ?, '', '');
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw FixtureError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
    sqlite3_bind_text(stmt, 1, uri, -1, transient)
    sqlite3_bind_text(stmt, 2, framework, -1, transient)
    sqlite3_bind_text(stmt, 3, title, -1, transient)
    sqlite3_bind_text(stmt, 4, "stub body", -1, transient)
    guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw FixtureError.execFailed(String(cString: sqlite3_errmsg(db)))
    }
}

private func countRows(_ db: OpaquePointer, sql: String) throws -> Int {
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw FixtureError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int(stmt, 0))
}

private func uriExists(_ db: OpaquePointer, uri: String, in table: String) throws -> Bool {
    let sql = "SELECT COUNT(*) FROM \(table) WHERE uri = ?;"
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw FixtureError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
    sqlite3_bind_text(stmt, 1, uri, -1, transient)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
    return sqlite3_column_int(stmt, 0) > 0
}

/// Build the canonical (post-#283) URI a row should have, matching what the
/// migration's planner computes.
private func canonicalURI(framework: String, url: String) -> String {
    let canonical = URLUtilities.filename(from: URL(string: url)!)
    return "apple-docs://\(framework)/\(canonical)"
}

// MARK: - Pure planner tests

@Suite("v13 URI rename planner (#283)")
struct V13PlannerTests {
    typealias Row = Search.Index.V13MetadataRow

    @Test("Empty input produces empty plan")
    func emptyInput() {
        let plan = Search.Index.v13PlanRenames(from: [])
        #expect(plan.renames.isEmpty)
        #expect(plan.deletions.isEmpty)
    }

    @Test("Already-canonical rows produce no work")
    func alreadyCanonical() {
        let url = "https://developer.apple.com/documentation/foundation/urlsession"
        let canonical = canonicalURI(framework: "foundation", url: url)
        let row = Row(uri: canonical, framework: "foundation", url: url, lastCrawled: 100)
        let plan = Search.Index.v13PlanRenames(from: [row])
        #expect(plan.renames.isEmpty)
        #expect(plan.deletions.isEmpty)
    }

    @Test("Single non-canonical row is renamed, no deletion")
    func singleRename() {
        // The row's URI is artificially mis-cased; the planner should rewrite it.
        let url = "https://developer.apple.com/documentation/Swift/withTaskGroup(of:returning:isolation:body:)"
        let stale = "apple-docs://swift/STALE_NONCANONICAL_KEY"
        let row = Row(uri: stale, framework: "swift", url: url, lastCrawled: 100)

        let plan = Search.Index.v13PlanRenames(from: [row])
        #expect(plan.deletions.isEmpty)
        let canonical = canonicalURI(framework: "swift", url: url)
        #expect(plan.renames[stale] == canonical)
    }

    @Test("Two case-variant rows: newer wins, older deleted")
    func twoVariantsNewerWins() {
        // Both rows reference Apple URLs that differ only in case. Both
        // pre-#283 URIs are non-canonical, so both are rename candidates;
        // they collide on the same target URI, so the newer survives.
        let urlCapital = "https://developer.apple.com/documentation/Swift/withTaskGroup(of:returning:isolation:body:)"
        let urlLower = "https://developer.apple.com/documentation/swift/withtaskgroup(of:returning:isolation:body:)"
        let older = Row(uri: "apple-docs://swift/STALE_CAPITAL", framework: "swift", url: urlCapital, lastCrawled: 100)
        let newer = Row(uri: "apple-docs://swift/STALE_LOWER", framework: "swift", url: urlLower, lastCrawled: 200)

        let plan = Search.Index.v13PlanRenames(from: [older, newer])
        let canonical = canonicalURI(framework: "swift", url: urlLower)
        #expect(plan.renames[newer.uri] == canonical, "newer row should be the survivor")
        #expect(plan.deletions.contains(older.uri))
        #expect(plan.deletions.count == 1)
        #expect(plan.renames.count == 1)
    }

    @Test("Three case-variant rows: newest survives, two deletions")
    func threeVariants() {
        let baseURL = "https://developer.apple.com/documentation/Observation/Observable()"
        let oldest = Row(uri: "apple-docs://observation/STALE_A", framework: "observation", url: baseURL, lastCrawled: 100)
        let newest = Row(uri: "apple-docs://observation/STALE_B", framework: "observation", url: baseURL, lastCrawled: 300)
        let middle = Row(uri: "apple-docs://observation/STALE_C", framework: "observation", url: baseURL, lastCrawled: 200)

        let plan = Search.Index.v13PlanRenames(from: [oldest, newest, middle])
        #expect(plan.renames.count == 1)
        #expect(plan.renames.keys.first == newest.uri, "newest has the highest last_crawled")
        #expect(plan.deletions == [oldest.uri, middle.uri])
    }

    @Test("Rename target collides with pre-existing canonical row: all variants deleted")
    func collisionWithExistingCanonical() {
        // canonicalRow is already canonical. variantRow is a case-variant
        // pointing at the same logical page. Even though variantRow is newer,
        // the planner should NOT overwrite canonicalRow's key; it deletes
        // variantRow instead. This guards the "the new URI is already taken
        // by a row we wouldn't otherwise touch" branch in `v13PlanRenames`.
        let url = "https://developer.apple.com/documentation/foundation/urlsession"
        let canonical = canonicalURI(framework: "foundation", url: url)

        let canonicalRow = Row(uri: canonical, framework: "foundation", url: url, lastCrawled: 100)
        let variantRow = Row(
            uri: "apple-docs://foundation/STALE_VARIANT",
            framework: "foundation",
            url: url,
            lastCrawled: 999
        )

        let plan = Search.Index.v13PlanRenames(from: [canonicalRow, variantRow])
        #expect(plan.renames.isEmpty, "canonical row stays untouched")
        #expect(plan.deletions == [variantRow.uri])
    }
}

// MARK: - Integration tests

@Suite("v13 URI rename migration end-to-end (#283)")
struct V13MigrationIntegrationTests {
    /// Build a fresh DB through `Search.Index` (so the schema is created),
    /// disconnect, downgrade `PRAGMA user_version` to 12, seed synthetic
    /// case-variant rows directly via SQL, then close. The DB now looks like
    /// a pre-migration v12 corpus to the next opener.
    private func seedV12Fixture(at dbPath: URL, _ seed: (OpaquePointer) throws -> Void) async throws {
        // Create-and-init creates v13 tables and stamps user_version = 13.
        let bootstrap = try await Search.Index(dbPath: dbPath)
        await bootstrap.disconnect()

        try withRawDB(at: dbPath) { db in
            try exec(db, "PRAGMA user_version = 12;")
            try seed(db)
        }
    }

    @Test("Two case-variant rows collapse to one canonical row after migration")
    func twoVariantsCollapse() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let urlCapital = "https://developer.apple.com/documentation/Swift/withTaskGroup(of:returning:isolation:body:)"
        let urlLower = "https://developer.apple.com/documentation/swift/withtaskgroup(of:returning:isolation:body:)"
        let staleCapital = "apple-docs://swift/STALE_CAPITAL"
        let staleLower = "apple-docs://swift/STALE_LOWER"

        try await seedV12Fixture(at: dbPath) { db in
            try insertMetadataRow(db, uri: staleCapital, framework: "swift", url: urlCapital, lastCrawled: 100)
            try insertMetadataRow(db, uri: staleLower, framework: "swift", url: urlLower, lastCrawled: 200)
            try insertFTSRow(db, uri: staleCapital, framework: "swift", title: "withTaskGroup")
            try insertFTSRow(db, uri: staleLower, framework: "swift", title: "withtaskgroup")
        }

        // Re-opening triggers checkAndMigrateSchema -> migrateToVersion13.
        let migrated = try await Search.Index(dbPath: dbPath)
        await migrated.disconnect()

        try withRawDB(at: dbPath) { db in
            let metaCount = try countRows(db, sql: "SELECT COUNT(*) FROM docs_metadata;")
            let ftsCount = try countRows(db, sql: "SELECT COUNT(*) FROM docs_fts;")
            #expect(metaCount == 1)
            #expect(ftsCount == 1)

            // Both URLs canonicalize to the same URI; the lower-case row
            // (last_crawled = 200) was the survivor.
            let canonical = canonicalURI(framework: "swift", url: urlLower)
            let canonicalInMeta = try uriExists(db, uri: canonical, in: "docs_metadata")
            let canonicalInFTS = try uriExists(db, uri: canonical, in: "docs_fts")
            let staleCapitalGone = try !uriExists(db, uri: staleCapital, in: "docs_metadata")
            let staleLowerGone = try !uriExists(db, uri: staleLower, in: "docs_metadata")
            #expect(canonicalInMeta)
            #expect(canonicalInFTS)
            #expect(staleCapitalGone)
            #expect(staleLowerGone)
        }
    }

    @Test("Migration is idempotent: second open is a no-op")
    func idempotent() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let url = "https://developer.apple.com/documentation/Observation/Observable()"
        try await seedV12Fixture(at: dbPath) { db in
            try insertMetadataRow(db, uri: "apple-docs://observation/STALE", framework: "observation", url: url, lastCrawled: 100)
        }

        // First open: runs the migration.
        let firstOpen = try await Search.Index(dbPath: dbPath)
        await firstOpen.disconnect()

        // Snapshot post-migration state.
        var rowCountAfterFirst = 0
        try withRawDB(at: dbPath) { db in
            rowCountAfterFirst = try countRows(db, sql: "SELECT COUNT(*) FROM docs_metadata;")
        }

        // Second open: schema_version is 13 already; v13 migration must not
        // run (and if it did, it must still be a no-op).
        let secondOpen = try await Search.Index(dbPath: dbPath)
        await secondOpen.disconnect()

        try withRawDB(at: dbPath) { db in
            let rowCountAfterSecond = try countRows(db, sql: "SELECT COUNT(*) FROM docs_metadata;")
            #expect(rowCountAfterSecond == rowCountAfterFirst, "row count must not drift on re-open")
        }
    }

    // (canonical-no-op + idempotence already cover that the migration leaves
    // a clean v12 corpus untouched. No third integration test needed.)

    @Test("Already-canonical v12 DB migrates as a no-op (no spurious deletions)")
    func canonicalV12IsNoOp() async throws {
        let dbPath = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }

        let url = "https://developer.apple.com/documentation/foundation/urlsession"
        let canonical = canonicalURI(framework: "foundation", url: url)
        try await seedV12Fixture(at: dbPath) { db in
            // Single row whose URI is already the canonical form. Migration
            // must leave it untouched.
            try insertMetadataRow(db, uri: canonical, framework: "foundation", url: url, lastCrawled: 100)
            try insertFTSRow(db, uri: canonical, framework: "foundation", title: "URLSession")
        }

        let migrated = try await Search.Index(dbPath: dbPath)
        await migrated.disconnect()

        try withRawDB(at: dbPath) { db in
            let metaCount = try countRows(db, sql: "SELECT COUNT(*) FROM docs_metadata;")
            let inMeta = try uriExists(db, uri: canonical, in: "docs_metadata")
            let inFTS = try uriExists(db, uri: canonical, in: "docs_fts")
            #expect(metaCount == 1)
            #expect(inMeta)
            #expect(inFTS)
        }
    }
}
