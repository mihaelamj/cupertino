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
    /// A 5-second busy timeout absorbs transient lock contention from a
    /// concurrent writer.
    public static func openReadOnly(at url: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
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
}
