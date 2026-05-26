import Foundation
import SearchModels
import SQLite3

// MARK: - #759 / #755 iteration 2. hierarchy-walk constraint inheritance

extension Search.Index {
    /// Walk the doc_symbols table after primary indexing completes and
    /// fill in `generic_constraints` on method / property / nested-type
    /// rows that themselves have no constraint clause but whose parent
    /// TYPE declares constraints.
    ///
    /// **Why this exists.** SwiftUI mini-corpus measurement at the time
    /// of #759: 30.5% of Apple's docs declarations carry generic
    /// parameters; 61.9% of those have their constraint in the
    /// declaration itself (caught by the AST extractor's where-clause
    /// fix in iteration 1). The remaining 38.1% are "bare-generic
    /// methods": `nonisolated init(_:isActive:destination:)` on
    /// `NavigationLink<Label, Destination>` shows `() -> Destination`
    /// in its signature but the `Destination: View` constraint is on
    /// the parent struct, not the init. Without propagation, those
    /// 38.1% of rows stay NULL in `generic_constraints` and the
    /// `search_generics View` query misses every NavigationLink init
    /// even though they're View-constrained by inheritance.
    ///
    /// **Algorithm.**
    /// 1. Pass 1 (in memory): `SELECT doc_uri, generic_constraints FROM
    ///    doc_symbols WHERE generic_constraints IS NOT NULL AND kind IN
    ///    ('struct', 'class', 'enum', 'actor', 'protocol', 'typealias')`.
    ///    Build a `[doc_uri: String: constraint: String]` map keyed by
    ///    the type's own page URI.
    /// 2. Pass 2 (single UPDATE per matching row): for every row where
    ///    `generic_constraints IS NULL AND generic_params IS NOT NULL`,
    ///    derive the parent URI by stripping the last `/<segment>`
    ///    from `doc_uri`, look up the map, set the row's
    ///    `generic_constraints` to the parent's value if present.
    ///
    /// **Idempotent.** Re-running against an already-propagated DB is a
    /// no-op because the WHERE clause excludes rows that already have
    /// `generic_constraints` set. Safe to call multiple times.
    ///
    /// **Carmack note (#759 epic).** A single SQL UPDATE WITH JOIN
    /// could do this without the in-memory map, but the URI string
    /// manipulation needed to compute parent_uri inside SQLite (no
    /// reliable string-split builtin; would need nested SUBSTR with
    /// REVERSE-and-INSTR tricks that don't survive corpus-shape edge
    /// cases like trailing slashes or URI-encoded segments) is worse
    /// than the O(N) memory dictionary. Cost: ~120k entries × ~80
    /// bytes/entry = ~10 MB for the full v1.0.x corpus. Negligible
    /// against the 2.3 GB raw markdown the indexer already streams.
    @discardableResult
    public func propagateConstraintsFromParents() async throws -> Int {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Pass 1. build the parent map.
        let parentMap = try buildParentConstraintsMap(database)

        guard !parentMap.isEmpty else {
            // No type rows carry constraints; nothing to propagate.
            return 0
        }

        // Pass 2. update each child row whose parent lives in the map.
        return try applyInheritedConstraints(database, parentMap: parentMap)
    }

    /// Pass 1: collect parent-type rows whose `generic_constraints`
    /// are non-null. Stores both the constraint blob AND the parent's
    /// type-parameter names. iteration 2 needs the names to decide
    /// whether a child symbol's signature actually references the
    /// parent's generics (and thus genuinely inherits the constraints)
    /// vs. living incidentally under the same URI (where inheriting
    /// would be a false positive).
    ///
    /// Example: `ForEach<Data, ID, Content>` parent row stores
    /// `(constraints: "RandomAccessCollection,Hashable", paramNames:
    /// ["Data", "ID", "Content"])`. A child page
    /// `apple-docs://swiftui/foreach/init-...` whose signature
    /// references `Data` or `Content` is a true generic-API surface;
    /// a child page that doesn't reference any parent name (rare for
    /// methods on generic types but possible. e.g. a static
    /// non-generic helper) is left alone.
    ///
    /// Filtered to type kinds (struct / class / enum / actor /
    /// protocol / typealias). Methods and properties are never
    /// "parents" for the inheritance purpose; if a method has
    /// constraints in its own declaration, those constraints already
    /// landed in iteration 1's AST walk and don't need a second pass.
    private func buildParentConstraintsMap(
        _ database: OpaquePointer
    ) throws -> [String: (constraints: String, paramNames: [String])] {
        let sql = """
        SELECT doc_uri, generic_constraints, generic_params
        FROM doc_symbols
        WHERE generic_constraints IS NOT NULL
          AND kind IN ('struct', 'class', 'enum', 'actor', 'protocol', 'typealias');
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("buildParentConstraintsMap prepare failed: \(errorMessage)")
        }

        var map: [String: (constraints: String, paramNames: [String])] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uriPtr = sqlite3_column_text(statement, 0),
                  let consPtr = sqlite3_column_text(statement, 1) else {
                continue
            }
            let uri = String(cString: uriPtr)
            let constraints = String(cString: consPtr)
            let paramsCstr = sqlite3_column_text(statement, 2)
            let paramsStr = paramsCstr.map { String(cString: $0) } ?? ""
            let paramNames = Self.extractBareParamNames(from: paramsStr)
            // If multiple type rows share the same doc_uri (rare; e.g.
            // a typealias on the same page as a struct of the same
            // name), keep the entry with the most informative
            // constraint string.
            if let existing = map[uri], existing.constraints.count >= constraints.count {
                continue
            }
            map[uri] = (constraints, paramNames)
        }

        return map
    }

    /// Pass 2: for every NULL-constraints row, look up the row's
    /// parent URI in the map and decide whether to inherit. Two
    /// inheritance triggers:
    ///
    /// 1. **Own generic params** (the row declares its own generic
    ///    clause that lacked constraints. bare names like `<T>`).
    ///    The parent's full constraint blob attaches to the row.
    ///    Catches typealiases / nested types whose own declaration
    ///    skipped the constraint clause but lives in a constrained
    ///    scope.
    ///
    /// 2. **Signature references a parent type-parameter name**. The
    ///    row's own declaration has no generic clause at all (empty
    ///    `generic_params`), but its signature uses one of the
    ///    parent type's generic names (e.g. NavigationLink's
    ///    `init(...) -> NavigationLink<Label, Destination>` uses
    ///    `Destination` from the parent struct). Word-boundary
    ///    identifier match against the parent's bare param names.
    ///
    /// Both triggers UPDATE the row's `generic_constraints` to the
    /// parent's blob. Rows that fail both triggers stay NULL. the
    /// row genuinely doesn't live in the parent's generic surface
    /// (e.g. a static non-generic helper).
    ///
    /// "Parent URI" = the row's `doc_uri` with the last path segment
    /// stripped. Example:
    /// `apple-docs://swiftui/navigationlink/init-isactive-destination`
    /// → parent = `apple-docs://swiftui/navigationlink`.
    private func applyInheritedConstraints(
        _ database: OpaquePointer,
        parentMap: [String: (constraints: String, paramNames: [String])]
    ) throws -> Int {
        let selectSQL = """
        SELECT id, doc_uri, generic_params, signature
        FROM doc_symbols
        WHERE generic_constraints IS NULL;
        """

        var selectStmt: OpaquePointer?
        defer { sqlite3_finalize(selectStmt) }

        guard sqlite3_prepare_v2(database, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("applyInheritedConstraints select prepare failed: \(errorMessage)")
        }

        // Collect (id, inherited constraint) pairs in one pass, then
        // bulk-update outside the SELECT cursor. SQLite forbids
        // UPDATE-while-iterating on the same table in the same prepared
        // statement; staging the work is the safe shape.
        var updates: [(id: Int64, constraints: String)] = []
        while sqlite3_step(selectStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(selectStmt, 0)
            guard let uriPtr = sqlite3_column_text(selectStmt, 1) else {
                continue
            }
            let childUri = String(cString: uriPtr)
            guard let parentUri = Self.parentURI(of: childUri),
                  let parent = parentMap[parentUri] else {
                continue
            }

            // Trigger 1: child has its own generic params (bare or
            // partial). Inherit unconditionally. the row's own
            // declaration entered the generic surface.
            let paramsCstr = sqlite3_column_text(selectStmt, 2)
            let paramsStr = paramsCstr.map { String(cString: $0) } ?? ""
            let hasOwnGenericParams = !paramsStr.isEmpty

            // Trigger 2: child's signature references at least one
            // of the parent's generic-param NAMES as a word-boundary
            // identifier. Word boundaries avoid false positives like
            // `RowValue` matching `Row` (no false match. substring
            // matching here would have flagged it; word-boundary
            // doesn't). Catches the bare-generic methods case where
            // the method itself has no `<...>` clause.
            let sigCstr = sqlite3_column_text(selectStmt, 3)
            let signature = sigCstr.map { String(cString: $0) } ?? ""
            let sigReferencesParent = !signature.isEmpty
                && Self.signatureReferencesAnyParam(signature, paramNames: parent.paramNames)

            guard hasOwnGenericParams || sigReferencesParent else {
                continue
            }
            updates.append((id, parent.constraints))
        }

        guard !updates.isEmpty else {
            return 0
        }

        // Apply staged updates in a single transaction. The N row
        // updates are independent; transactioning avoids per-statement
        // fsync overhead on the WAL.
        let updateSQL = "UPDATE doc_symbols SET generic_constraints = ? WHERE id = ?;"
        var updateStmt: OpaquePointer?
        defer { sqlite3_finalize(updateStmt) }
        guard sqlite3_prepare_v2(database, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("applyInheritedConstraints update prepare failed: \(errorMessage)")
        }

        guard sqlite3_exec(database, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.sqliteError("propagateConstraintsFromParents BEGIN failed: \(errorMessage)")
        }

        for (id, constraints) in updates {
            sqlite3_reset(updateStmt)
            sqlite3_bind_text(updateStmt, 1, (constraints as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(updateStmt, 2, id)
            if sqlite3_step(updateStmt) != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw Search.Error.sqliteError("propagateConstraintsFromParents update step failed: \(errorMessage)")
            }
        }

        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw Search.Error.sqliteError("propagateConstraintsFromParents COMMIT failed: \(errorMessage)")
        }
        return updates.count
    }

    /// Extract bare type-parameter NAMES from the `generic_params`
    /// column shape. Input examples:
    /// - `"T"`                                                  → `["T"]`
    /// - `"Data,ID,Content"`                                    → `["Data", "ID", "Content"]`
    /// - `"Data,ID,Content,Data: RandomAccessCollection,ID: Hashable"`
    ///   (post-#759 AST output: bare entries + `Name: Constraint` entries
    ///   joined by the GenericWhereClause walk)
    ///   → `["Data", "ID", "Content"]`
    /// - `""`                                                   → `[]`
    ///
    /// The function de-duplicates so the same name appearing in both
    /// the bare-list AND a where-clause entry doesn't get matched
    /// twice in iteration 2's signature scan. Empty input returns
    /// an empty array (no parent param scope to match against).
    static func extractBareParamNames(from genericParams: String) -> [String] {
        guard !genericParams.isEmpty else {
            return []
        }
        var seen: Set<String> = []
        var ordered: [String] = []
        for raw in genericParams.split(separator: ",") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // Take everything before the `:` (constraint clause), if
            // any. `"Data: RandomAccessCollection"` → `"Data"`.
            let name: String
            if let colon = trimmed.firstIndex(of: ":") {
                name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            } else {
                name = trimmed
            }
            guard !name.isEmpty, !seen.contains(name) else {
                continue
            }
            seen.insert(name)
            ordered.append(name)
        }
        return ordered
    }

    /// Does `signature` reference any name in `paramNames` as a
    /// word-boundary identifier? Word boundary = preceding character
    /// is not an identifier char (letter / digit / underscore) and
    /// trailing character is similarly bounded. Catches:
    /// - `() -> Destination`       (after-space, end-of-string → match)
    /// - `Binding<Destination>`    (after-`<`, before-`>` → match)
    /// - `Content)`                (after-space, before-`)` → match)
    ///
    /// Rejects:
    /// - `DestinationKey`          (`Destination` followed by `K` → not a word boundary at the right side)
    /// - `RowValue` against `Row`  (`Row` followed by `V` → no match)
    ///
    /// Empty `paramNames` short-circuits to false (no parent scope).
    static func signatureReferencesAnyParam(_ signature: String, paramNames: [String]) -> Bool {
        guard !paramNames.isEmpty else {
            return false
        }
        // Use NSRegularExpression with `\b<name>\b` patterns. One
        // alternation matches any param.
        let escaped = paramNames.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(" + escaped.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(signature.startIndex..<signature.endIndex, in: signature)
        return regex.firstMatch(in: signature, options: [], range: range) != nil
    }

    /// Strip the final path segment from a URI. Returns nil for URIs
    /// that have no `/` to strip (or one that's part of the scheme
    /// separator only. `apple-docs://`).
    ///
    /// Examples:
    /// `apple-docs://swiftui/navigationlink/init-foo` → `apple-docs://swiftui/navigationlink`
    /// `apple-docs://swiftui/navigationlink`          → `apple-docs://swiftui`
    /// `apple-docs://swiftui`                         → `apple-docs:` (scheme tail; lookup returns nil downstream, so safe)
    /// `bare-string`                                  → nil
    static func parentURI(of uri: String) -> String? {
        guard let lastSlash = uri.lastIndex(of: "/") else {
            return nil
        }
        // Refuse to strip if the only slashes are the `://` of the scheme.
        // Lookup against `apple-docs:` would never match anyway, but
        // returning nil here is cheaper and the intent is clearer.
        let prefix = uri[..<lastSlash]
        if prefix.hasSuffix(":/") {
            return nil
        }
        return String(prefix)
    }
}
