import Foundation
import SearchModels
import SQLite3

// MARK: - #759 iteration 3. authoritative static-table apply

extension Search.Index {
    /// Apply the authoritative Apple-type constraints table over the
    /// `doc_symbols.generic_constraints` column.
    ///
    /// Runs after iteration 1 (AST extractor's where-clause walk in
    /// `Search.Index.IndexingDocs`) and BEFORE iteration 2's
    /// hierarchy walk (`propagateConstraintsFromParents`). The
    /// ordering matters: iter 3 overrides iter 1's results for the
    /// type-level rows the table covers, then iter 2's parent map
    /// reads from the post-iter-3 state so the hierarchy walk
    /// propagates the authoritative values down to bare-generic
    /// methods.
    ///
    /// **Match shapes.** Each entry's `docURI` is the
    /// un-disambiguated form (Apple's `pathComponents` joined
    /// lowercase). For each entry:
    /// 1. Exact match: `doc_symbols.doc_uri = entry.docURI`.
    ///    Catches type-level rows + methods without overload
    ///    disambiguation.
    /// 2. Hash-prefix match: `doc_symbols.doc_uri LIKE entry.docURI ||
    ///    '-%'`. Catches Apple's hash-disambiguated overloads
    ///    (`init(_:content:)-7l1jb`).
    ///
    /// Both UPDATE the row's `generic_constraints` to the joined-
    /// comma blob from `entry.constraints`. Last-write-wins if
    /// entries duplicate a URI; the upstream extractor dedups, so
    /// duplicates here would be a bug in the generator.
    ///
    /// **Transactioned** (per `Search.Index.HierarchyConstraints`
    /// pattern). The N entry-updates run inside one BEGIN/COMMIT pair
    /// for write-throughput on the WAL.
    ///
    /// **Optional dependency.** If `lookup` is nil (no static table
    /// configured at the composition root), the method returns
    /// immediately without touching the DB.
    @discardableResult
    public func applyAppleStaticConstraints(
        lookup: (any Search.StaticConstraintsLookup)?
    ) async throws -> Int {
        guard let lookup, let database else {
            return 0
        }
        let entries = try await lookup.allEntries()
        guard !entries.isEmpty else {
            return 0
        }

        // Both prepared statements stay alive across the entry loop ,
        // SQLite reuses the bytecode per re-bind, which is the
        // canonical N-row UPDATE shape.
        let exactSQL = """
        UPDATE doc_symbols
        SET generic_constraints = ?
        WHERE doc_uri = ?;
        """
        let prefixSQL = """
        UPDATE doc_symbols
        SET generic_constraints = ?
        WHERE doc_uri LIKE ?;
        """

        var exactStmt: OpaquePointer?
        var prefixStmt: OpaquePointer?
        defer {
            sqlite3_finalize(exactStmt)
            sqlite3_finalize(prefixStmt)
        }
        guard sqlite3_prepare_v2(database, exactSQL, -1, &exactStmt, nil) == SQLITE_OK,
              sqlite3_prepare_v2(database, prefixSQL, -1, &prefixStmt, nil) == SQLITE_OK
        else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("applyAppleStaticConstraints prepare failed: \(errorMessage)")
        }

        guard sqlite3_exec(database, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("applyAppleStaticConstraints BEGIN failed: \(errorMessage)")
        }

        var affected = 0
        for entry in entries {
            let joined = entry.constraints.joined(separator: ",")
            let likePattern = entry.docURI + "-%"

            sqlite3_reset(exactStmt)
            sqlite3_bind_text(exactStmt, 1, (joined as NSString).utf8String, -1, nil)
            sqlite3_bind_text(exactStmt, 2, (entry.docURI as NSString).utf8String, -1, nil)
            guard sqlite3_step(exactStmt) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("applyAppleStaticConstraints exact-update failed: \(errorMessage)")
            }
            affected += Int(sqlite3_changes(database))

            sqlite3_reset(prefixStmt)
            sqlite3_bind_text(prefixStmt, 1, (joined as NSString).utf8String, -1, nil)
            sqlite3_bind_text(prefixStmt, 2, (likePattern as NSString).utf8String, -1, nil)
            guard sqlite3_step(prefixStmt) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("applyAppleStaticConstraints prefix-update failed: \(errorMessage)")
            }
            affected += Int(sqlite3_changes(database))
        }

        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw Search.Error.sqliteError("applyAppleStaticConstraints COMMIT failed: \(errorMessage)")
        }
        return affected
    }
}
