import Foundation
import SQLite3
import SQLiteSupport

extension Diagnostics.Probes {
    /// Outcome of a structural integrity probe (`PRAGMA quick_check`).
    public enum IntegrityResult: Sendable, Equatable {
        /// The file opened read-only and `quick_check` reported `ok`:
        /// every b-tree page was read and is structurally consistent.
        case ok
        /// The file could not be opened read-only, or a page read failed
        /// mid-scan. Carries the underlying SQLite message — "disk I/O
        /// error" (the OS could not read a page back: truncated extract,
        /// failing / cloud-evicted volume) or a generic open failure.
        case unreadable(String)
        /// `quick_check` opened and scanned the file but reported
        /// structural problems ("database disk image is malformed" and
        /// friends): a corrupt or partially-written copy. Carries the
        /// reported problem lines (capped by the caller).
        case problems([String])
    }

    /// Run `PRAGMA quick_check` against `dbPath` on a read-only connection
    /// and classify the result.
    ///
    /// The header-only probes (`userVersion`, `journalMode`) and the
    /// single-table count probes all succeed on a file whose header and
    /// shallow pages are intact but whose deeper pages cannot be read —
    /// the failure mode behind discussion #1276, where a downloaded
    /// `apple-documentation.db` opened fine and answered `sqlite_master`,
    /// then threw "disk I/O error" on the first real `search` /
    /// `list_frameworks` query at serve time. `quick_check` walks every
    /// page of every b-tree, so it surfaces that damage at `cupertino
    /// setup` time (with an actionable message) instead of silently
    /// passing setup's existence check. Read-only; never writes.
    public static func quickCheck(at dbPath: URL) -> IntegrityResult {
        guard let db = openReadOnlyProbe(at: dbPath) else {
            return .unreadable("could not open \(dbPath.lastPathComponent) read-only")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check;", -1, &stmt, nil) == SQLITE_OK else {
            return .unreadable(String(cString: sqlite3_errmsg(db)))
        }

        var rows: [String] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                if let text = sqlite3_column_text(stmt, 0) {
                    rows.append(String(cString: text))
                }
                continue
            }
            if rc == SQLITE_DONE {
                break
            }
            // Any other code (notably SQLITE_IOERR) means a page read
            // failed partway through the scan — the file is on disk but
            // unreadable. This is the "disk I/O error" path.
            return .unreadable(String(cString: sqlite3_errmsg(db)))
        }

        // A clean database reports exactly one row: "ok".
        if rows == ["ok"] {
            return .ok
        }
        return .problems(rows)
    }
}
