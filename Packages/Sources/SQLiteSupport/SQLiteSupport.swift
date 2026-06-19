import Foundation
import SQLite3

// MARK: - SQLiteSupport

/// Low-level, schema-agnostic SQLite connection helpers shared by every
/// cupertino reader (`Search.Index`, `Sample.Index.Database`,
/// `Search.PackageQuery`). Keeping the open in ONE place guarantees every
/// database is opened the same way, with no per-DB special-casing of how
/// a read connection is established.
///
/// This is a concrete producer (it imports the `SQLite3` system library), so
/// it deliberately lives outside the foundation-only model/seam tier.
public enum SQLiteSupport {
    public enum OpenError: Error, CustomStringConvertible {
        case readOnlyOpenFailed(path: String, message: String)

        public var description: String {
            switch self {
            case .readOnlyOpenFailed(let path, let message):
                "Failed to open \(path) read-only: \(message)"
            }
        }
    }

    /// Open the database at `url` as a strictly read-only connection.
    ///
    /// Uses `SQLITE_OPEN_READONLY`: the handle is physically incapable of
    /// writing, so INSERT / UPDATE / DELETE / DDL all fail with
    /// `SQLITE_READONLY`. This is the single open path every query / read /
    /// serve / list reader uses so an end user cannot write or delete rows in
    /// any shipped database (#1194).
    ///
    /// A read-only open needs no `-shm` shared-memory sidecar on a rollback
    /// (DELETE) journal-mode database, which is how cupertino ships its
    /// bundles (#1192); when the DB is in WAL mode with an existing `-shm`
    /// (a locally-indexed database), the read connection honours the WAL.
    ///
    /// The edge case this guards (found reproducing #88's empty-tree probe on a
    /// locally-built corpus): a **WAL-mode database whose `-shm` sidecar is
    /// absent**. A read-only connection cannot create the `-shm` a WAL database
    /// needs, so `sqlite3_open_v2` SUCCEEDS but the first read traps with
    /// `SQLITE_CANTOPEN` — which a naive caller misreads as "schema version 0,
    /// rebuild required" even though the file is intact. When the `-wal` has no
    /// pending frames (absent or zero-length), the committed state lives wholly
    /// in the main database file, so reopening `immutable=1` — which bypasses
    /// the `-wal`/`-shm` machinery and reads the file directly — is correct, not
    /// merely a workaround. When the `-wal` DOES carry frames, reading immutable
    /// would silently skip them, so we fail honestly and ask for a checkpoint
    /// rather than return stale data. A 5-second busy timeout absorbs transient
    /// lock contention from a concurrent writer.
    public static func openReadOnly(at url: URL) throws -> OpaquePointer {
        let handle = try open(url, immutable: false)
        if canRead(handle) {
            return handle
        }

        // The strict read-only open succeeded but the first read failed — the
        // WAL-without-`-shm` case described above.
        sqlite3_close(handle)
        guard walIsEmpty(for: url) else {
            throw OpenError.readOnlyOpenFailed(
                path: url.path,
                message: "WAL-mode database has pending frames and no readable -shm sidecar; "
                    + "checkpoint it (open read-write once) before read-only access"
            )
        }

        let immutableHandle = try open(url, immutable: true)
        guard canRead(immutableHandle) else {
            sqlite3_close(immutableHandle)
            throw OpenError.readOnlyOpenFailed(
                path: url.path,
                message: "database could not be read even as immutable; it may be corrupt or truncated"
            )
        }
        return immutableHandle
    }

    /// Open a read-only handle, optionally with the `immutable=1` URI parameter
    /// (which tells SQLite the file and its WAL will not change, so it reads the
    /// main file directly without the `-wal`/`-shm` machinery).
    private static func open(_ url: URL, immutable: Bool) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let flags: Int32 = immutable ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_URI) : SQLITE_OPEN_READONLY
        let target: String
        if immutable {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw OpenError.readOnlyOpenFailed(path: url.path, message: "could not form a file URI for immutable open")
            }
            components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
            guard let uri = components.string else {
                throw OpenError.readOnlyOpenFailed(path: url.path, message: "could not form an immutable file URI")
            }
            target = uri
        } else {
            target = url.path
        }

        guard sqlite3_open_v2(target, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite3 error"
            sqlite3_close(handle)
            throw OpenError.readOnlyOpenFailed(path: url.path, message: message)
        }
        guard let handle else {
            throw OpenError.readOnlyOpenFailed(path: url.path, message: "sqlite3_open_v2 returned a nil handle")
        }
        sqlite3_busy_timeout(handle, 5000)
        return handle
    }

    /// Whether the connection can actually read the database, not just its header. We probe with
    /// `SELECT count(*) FROM sqlite_master`, which forces SQLite to read the schema b-tree: it
    /// fails (non-row step) on a WAL database with no accessible `-shm` (the case the immutable
    /// fallback exists for) AND on a database whose schema b-tree is corrupt. A header-only probe
    /// (`PRAGMA user_version`) would pass on a corrupt or unreadable-table file because it only
    /// reads the intact 100-byte header. An empty database still has an (empty) `sqlite_master`,
    /// so this yields a row there, distinguishing genuinely-empty from unreadable.
    private static func canRead(_ handle: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "SELECT count(*) FROM sqlite_master", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Whether the database's `-wal` sidecar carries no pending frames (absent or
    /// zero-length). When true, the committed state is wholly in the main file,
    /// so an `immutable=1` read cannot miss data.
    private static func walIsEmpty(for url: URL) -> Bool {
        let walPath = url.path + "-wal"
        guard FileManager.default.fileExists(atPath: walPath) else { return true }
        let size = (try? FileManager.default.attributesOfItem(atPath: walPath)[.size]) as? Int
        return (size ?? 0) == 0
    }
}
