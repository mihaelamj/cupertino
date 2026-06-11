import Foundation
import SearchModels
import SQLite3

// MARK: - Apple SDK conformance-graph apply (conformance sibling of #759 iter 3)

extension Search.Indexer {
    /// Apply the authoritative Apple SDK conformance table over the
    /// `doc_symbols.conformances` column. Conformance analogue of
    /// `applyAppleStaticConstraints`: the rendered DocC markdown spells out a
    /// fraction of an Apple type's conformances; the symbol-graph carries the
    /// full set (~108k edges vs ~8.6k AST-extracted in the DB).
    ///
    /// **Match shapes** (identical to the constraints apply):
    /// 1. Exact: `doc_symbols.doc_uri = entry.docURI`.
    /// 2. Hash-prefix: `doc_symbols.doc_uri LIKE entry.docURI || '-%'` for
    ///    Apple's hash-disambiguated overload URIs.
    ///
    /// Both OVERWRITE `conformances` with the joined-comma blob from
    /// `entry.conformsTo` (the symbol-graph set is authoritative + complete,
    /// superseding the AST-extracted value for matched Apple rows). Non-matched
    /// rows keep their AST conformances. Transactioned; idempotent. No-op when
    /// `lookup` is nil.
    @discardableResult
    public func applyAppleStaticConformances(
        lookup: (any Search.StaticConformancesLookup)?,
        audit: (any Search.EnrichmentAuditObserver)? = nil,
        dbPath: String = ""
    ) async throws -> Int {
        guard let lookup, let database else {
            return 0
        }
        let entries = try await lookup.allConformanceEntries()
        guard !entries.isEmpty else {
            return 0
        }
        audit?.recordPassStart(passIdentifier: "apple-conformances", dbPath: dbPath)
        let startedAt = Date()

        let exactSQL = """
        UPDATE doc_symbols
        SET conformances = ?
        WHERE doc_uri = ?;
        """
        let prefixSQL = """
        UPDATE doc_symbols
        SET conformances = ?
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
            throw Search.Error.sqliteError("applyAppleStaticConformances prepare failed: \(errorMessage)")
        }

        guard sqlite3_exec(database, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("applyAppleStaticConformances BEGIN failed: \(errorMessage)")
        }

        var affected = 0
        for entry in entries {
            let joined = entry.conformsTo.joined(separator: ",")
            let likePattern = entry.docURI + "-%"

            sqlite3_reset(exactStmt)
            sqlite3_bind_text(exactStmt, 1, (joined as NSString).utf8String, -1, nil)
            sqlite3_bind_text(exactStmt, 2, (entry.docURI as NSString).utf8String, -1, nil)
            guard sqlite3_step(exactStmt) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("applyAppleStaticConformances exact-update failed: \(errorMessage)")
            }
            let exactChanges = Int(sqlite3_changes(database))
            affected += exactChanges
            if let audit, exactChanges > 0 {
                audit.recordEntry(
                    passIdentifier: "apple-conformances",
                    docURI: entry.docURI,
                    value: joined,
                    matchType: "exact",
                    rowsAffected: exactChanges
                )
            }

            sqlite3_reset(prefixStmt)
            sqlite3_bind_text(prefixStmt, 1, (joined as NSString).utf8String, -1, nil)
            sqlite3_bind_text(prefixStmt, 2, (likePattern as NSString).utf8String, -1, nil)
            guard sqlite3_step(prefixStmt) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("applyAppleStaticConformances prefix-update failed: \(errorMessage)")
            }
            let prefixChanges = Int(sqlite3_changes(database))
            affected += prefixChanges
            if let audit, prefixChanges > 0 {
                audit.recordEntry(
                    passIdentifier: "apple-conformances",
                    docURI: entry.docURI,
                    value: joined,
                    matchType: "prefix",
                    rowsAffected: prefixChanges
                )
            }
        }

        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw Search.Error.sqliteError("applyAppleStaticConformances COMMIT failed: \(errorMessage)")
        }
        audit?.recordPassEnd(
            passIdentifier: "apple-conformances",
            totalRowsAffected: affected,
            totalRowsSkipped: 0,
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
        return affected
    }
}
