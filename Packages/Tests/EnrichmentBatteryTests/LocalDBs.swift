import Foundation
import SQLite3

// Support for the enrichment battery: a set of local-only suites that
// probe the real per-source enriched DBs to prove each enrichment from
// docs/enrichment-inventory.md is present and correct in production data.
//
// The DBs are NOT in the repo (search.db alone is 2.9 GB), so every
// suite gates on a `*Available` flag via `.enabled(if:)`. A machine
// without the snapshot (CI, a fresh clone, another Mac) skips the suite
// cleanly instead of failing. Point at a different snapshot with the
// CUPERTINO_DB_DIR environment variable.

enum LocalDBs {
    static let dir: String = {
        if let env = ProcessInfo.processInfo.environment["CUPERTINO_DB_DIR"], !env.isEmpty {
            return env
        }
        return "/Volumes/Code/DeveloperExt/private/cupertino-dbs-2026-05-28"
    }()

    static let appleDocumentation = "apple-documentation.db"
    static let hig = "hig.db"
    static let swiftOrg = "swift-org.db"
    static let swiftBook = "swift-book.db"
    static let swiftEvolution = "swift-evolution.db"
    static let appleArchive = "apple-archive.db"
    static let appleSampleCode = "apple-sample-code.db"
    static let packages = "packages.db"

    /// The 6 DBs that share the docs schema.
    static let docsDBs = [appleDocumentation, hig, swiftOrg, swiftBook, swiftEvolution, appleArchive]

    static func path(_ db: String) -> String {
        "\(dir)/\(db)"
    }

    static func available(_ db: String) -> Bool {
        FileManager.default.fileExists(atPath: path(db))
    }

    static var anyDocsAvailable: Bool {
        docsDBs.contains(where: available)
    }

    static var samplesAvailable: Bool {
        available(appleSampleCode)
    }

    static var packagesAvailable: Bool {
        available(packages)
    }

    static var anyAvailable: Bool {
        anyDocsAvailable || samplesAvailable || packagesAvailable
    }

    /// The docs DBs that actually carry API symbols + code (HIG, swift-org,
    /// swift-book are prose / design sources with no doc_symbols rows).
    static var symbolBearingDocsDBs: [String] {
        [appleDocumentation].filter(available)
    }
}

/// Minimal read-only SQLite probe. Opened with SQLITE_OPEN_READONLY so a
/// battery can never mutate the snapshot it inspects. SQL is test-authored
/// (never user input), so string interpolation of identifiers is safe here.
final class DBProbe {
    private let handle: OpaquePointer

    init?(_ db: String) {
        var ptr: OpaquePointer?
        // immutable=1: read snapshots with no locking and no -shm/-wal access.
        // The suites run in parallel against WAL-mode DBs; without this, a
        // concurrent open contends on the shared-memory file and a transient
        // BUSY/LOCKED would surface as a false "table absent". The -wal files
        // are checkpointed (0 bytes), so immutable misses nothing.
        let uri = "file:\(LocalDBs.path(db))?immutable=1"
        guard sqlite3_open_v2(uri, &ptr, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let opened = ptr
        else {
            if let ptr { sqlite3_close(ptr) }
            return nil
        }
        handle = opened
    }

    deinit { sqlite3_close(handle) }

    /// Single Int64 from a single-row single-column query (e.g. COUNT(*)).
    func int(_ sql: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    func count(_ sql: String) -> Int64 {
        int(sql) ?? -1
    }

    /// First column of the first row as text.
    func text(_ sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    /// First column across every row.
    func column(_ sql: String) -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) { out.append(String(cString: cStr)) }
        }
        return out
    }

    func hasTable(_ name: String) -> Bool {
        (int("SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name='\(name)'") ?? 0) > 0
    }

    func tableColumns(_ table: String) -> [String] {
        column("SELECT name FROM pragma_table_info('\(table)')")
    }

    /// The CREATE statement for an object, for tokenizer / schema assertions.
    func createSQL(_ name: String) -> String? {
        text("SELECT sql FROM sqlite_master WHERE name='\(name)'")
    }
}
