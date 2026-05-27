import Foundation
import SearchModels
import SQLite3

// MARK: - HIG platform-inference pass

extension Search.Index {
    /// Narrows the `min_<platform>` columns on HIG rows whose URI
    /// declares an explicit platform target, NULL-ing the columns
    /// for platforms the topic doesn't cover. Pre-fix every HIG row
    /// had every `min_<platform>` column stamped at the earliest
    /// possible version (`min_ios=2.0`, `min_macos=10.0`, etc.) as
    /// a "available everywhere" default, even for obviously
    /// platform-specific topics like `hig://general/designing-for-watchos`
    /// or `hig://general/spatial-layout`. The result: a `--min-ios 16`
    /// search filter returned every HIG row including the watchOS
    /// and visionOS ones, since they all matched the iOS 2.0
    /// baseline.
    ///
    /// Post-fix: for each rule below, the matching URIs get the
    /// non-applicable platform columns set to NULL. Topics without
    /// an explicit platform keyword in the URI (the bulk of HIG —
    /// buttons, alerts, accessibility, color, layout) keep the
    /// cross-platform default per the existing indexer behaviour.
    ///
    /// **Known limitations.** Some watchOS-only topics like
    /// `activity-rings`, `complications`, `always-on` carry no
    /// "watch" keyword in their URI but ARE watchOS-first
    /// historically (some became cross-platform via Lock Screen
    /// complications + Activity app on iPhone). Conservative: leave
    /// them as cross-platform defaults. A page-content-aware
    /// inference is a follow-up.
    @discardableResult
    public func applyHIGPlatformInference(
        audit: (any Search.EnrichmentAuditObserver)? = nil,
        dbPath: String = ""
    ) async throws -> Int {
        guard let database else { return 0 }
        audit?.recordPassStart(passIdentifier: "hig-platforms", dbPath: dbPath)
        let startedAt = Date()

        // (URI LIKE pattern, platforms to KEEP populated)
        // Every other min_<platform> column gets set to NULL on a
        // matching row.
        let rules: [(pattern: String, keep: Set<String>)] = [
            ("%designing-for-watchos%", ["watchos"]),
            ("%watch-faces%", ["watchos"]),
            ("%designing-for-tvos%", ["tvos"]),
            ("%designing-for-visionos%", ["visionos"]),
            ("%spatial-layout%", ["visionos"]),
            ("%designing-for-macos%", ["macos"]),
            ("%mac-catalyst%", ["ios", "macos"]),
            ("%carplay%", ["ios"]),
            ("%designing-for-ipados%", ["ios"]),
            ("%designing-for-ios%", ["ios"]),
        ]
        let allPlatforms = ["ios", "macos", "tvos", "watchos", "visionos"]

        guard sqlite3_exec(database, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("applyHIGPlatformInference BEGIN failed: \(errorMessage)")
        }

        var totalAffected = 0
        for rule in rules {
            // Build the SET clause: NULL every non-kept platform.
            let nullClauses = allPlatforms
                .filter { !rule.keep.contains($0) }
                .map { "min_\($0) = NULL" }
                .joined(separator: ", ")
            guard !nullClauses.isEmpty else { continue }

            // Select matching URIs FIRST so the audit log carries
            // real per-URI evidence (mirrors AppleStaticConstraints
            // and HierarchyPass: every recordEntry's docURI is an
            // actual document URI, not a LIKE pattern). The SELECT
            // also lets us narrow the UPDATE to rows that still need
            // it (idempotent re-run accounting): only rows with a
            // non-NULL min_<other> column qualify.
            let needsUpdateClause = allPlatforms
                .filter { !rule.keep.contains($0) }
                .map { "min_\($0) IS NOT NULL" }
                .joined(separator: " OR ")
            let selectSQL = """
            SELECT uri FROM docs_metadata
            WHERE uri LIKE ?
              AND (\(needsUpdateClause));
            """
            var selectStmt: OpaquePointer?
            guard sqlite3_prepare_v2(database, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("applyHIGPlatformInference SELECT prepare failed: \(errorMessage)")
            }
            sqlite3_bind_text(selectStmt, 1, (rule.pattern as NSString).utf8String, -1, nil)
            var matchedURIs: [String] = []
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(selectStmt, 0) {
                    matchedURIs.append(String(cString: cStr))
                }
            }
            sqlite3_finalize(selectStmt)

            guard !matchedURIs.isEmpty else { continue }

            let sql = "UPDATE docs_metadata SET \(nullClauses) WHERE uri LIKE ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("applyHIGPlatformInference prepare failed: \(errorMessage)")
            }
            sqlite3_bind_text(stmt, 1, (rule.pattern as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("applyHIGPlatformInference step failed: \(errorMessage)")
            }
            totalAffected += matchedURIs.count
            if let audit {
                let value = "keep=\(rule.keep.sorted().joined(separator: ","))"
                for uri in matchedURIs {
                    audit.recordEntry(
                        passIdentifier: "hig-platforms",
                        docURI: uri,
                        value: value,
                        matchType: "uri-pattern",
                        rowsAffected: 1
                    )
                }
            }
        }

        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw Search.Error.sqliteError("applyHIGPlatformInference COMMIT failed: \(errorMessage)")
        }
        audit?.recordPassEnd(
            passIdentifier: "hig-platforms",
            totalRowsAffected: totalAffected,
            totalRowsSkipped: 0,
            durationMs: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
        return totalAffected
    }
}
