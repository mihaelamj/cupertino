import Foundation
import SearchModels
import SharedConstants
import SQLite3

/// #177 — shared signal-rank ORDER BY clause for the 4 AST semantic search
/// queries (`searchSymbols`, `searchPropertyWrappers`,
/// `searchConcurrencyPatterns`, `searchConformances`). Pre-fix every
/// query did a flat `ORDER BY s.name`, which surfaced `==(_:_:)` operator
/// overloads + synthesised `Equatable` / `Hashable` / `Comparable`
/// conformance members ahead of canonical type pages. A developer
/// searching for `mainactor` got `==` operators from RealityKit before
/// any real view-model class; `task` got `==` / `<=` / `<` on
/// `Task<Success, Failure>` and `TaskPriority` before any real Task
/// usage; etc.
///
/// Two-tier reranking deprioritises (does NOT exclude — that would
/// break "show me everything" workflows) the boilerplate:
///
/// Tier 1: rows whose symbol name is one of the auto-synthesised /
///   operator-overload names go LAST among everything else.
/// Tier 2: within tier 1, canonical type kinds (class / struct / enum /
///   protocol / actor) come first; type-shape sub-kinds (typealias /
///   macro) next; member-shape (method / function / property /
///   initializer) third; pages explicitly tagged `kind=operator`
///   fourth; everything else (including `kind=unknown`) in tier 5.
///
/// `s.name` ties remaining ordering — preserves the pre-fix alphabetic
/// shape for rows in the same kind+name-shape bucket.
private let signalRankOrderClause = """
ORDER BY
    CASE WHEN s.name IN (
        '==(_:_:)', '!=(_:_:)', '<(_:_:)', '<=(_:_:)', '>(_:_:)', '>=(_:_:)',
        '~=(_:_:)', 'hash(into:)',
        '==', '!=', '<', '<=', '>', '>='
    ) THEN 1 ELSE 0 END,
    CASE
        WHEN s.kind IN ('class', 'struct', 'enum', 'protocol', 'actor') THEN 0
        WHEN s.kind IN ('typealias', 'macro') THEN 1
        WHEN s.kind IN ('method', 'function', 'property', 'initializer', 'subscript', 'case') THEN 2
        WHEN s.kind = 'operator' THEN 3
        ELSE 4
    END,
    s.name
"""

/// #952: one-shot debug-only invariant check that
/// `signalRankOrderClause` begins with the literal `"ORDER BY\n"`
/// prefix that the property-wrapper search relies on for its
/// canonical-framework-boost splice. Evaluated lazily on first
/// reference (Swift evaluates `let` once per process); the
/// reference site is inside `searchPropertyWrappers`. In release
/// builds the assert is compiled out and the constant is
/// effectively `Void()`, zero runtime cost.
private let signalRankOrderClausePrefixCheck: Void = {
    assert(
        signalRankOrderClause.hasPrefix("ORDER BY\n"),
        "signalRankOrderClause prefix drifted; canonical-framework boost splice will produce malformed SQL"
    )
}()

/// #952: canonical-usage-framework lookup for `searchPropertyWrappers`.
///
/// Each Apple-defined property wrapper / attribute has one or more
/// frameworks where its USAGE examples are densest in the indexed
/// corpus. Pre-#952 the property-wrapper search used the shared
/// `signalRankOrderClause` whose tertiary tie-break is alphabetic
/// `s.name`. For `wrapper: "State"` the v1.2.x bundle has 537
/// SwiftUI `@State` usages + 2 `secureelementcredential` usages;
/// alphabetic ordering put `activeSession` (secureelementcredential)
/// at rank-1 ahead of all 537 SwiftUI hits because "active" sorts
/// before "adjust" / "alarms" / etc.
///
/// Post-#952 the `searchPropertyWrappers` SQL injects a new tier-0
/// boost: rows whose framework matches the queried wrapper's
/// canonical-usage set rank above all others. Wrappers not in this
/// table get no boost (ranking falls through to the existing
/// operator-demote / kind-shape tiers).
///
/// Lookup is case-insensitive on both wrapper and framework name.
/// Wrapper key is unprefixed (`State`, not `@State`).
///
/// The table targets the framework(s) where USAGE rows are densest,
/// NOT the framework where the wrapper attribute is declared.
/// `@MainActor` is declared in the Swift standard library but USED
/// across UIKit / SwiftUI / AppKit / RealityKit (988 / 915 / 753 /
/// 713 rows respectively in v1.2.x); a `["swift"]` boost would
/// have surfaced the single `swift`-framework `CoffeeData` sample
/// class above all 3,369 usage rows. Iter-2 of the #952 critic
/// loop caught and corrected this declaration-vs-usage mismatch.
///
/// Wrappers with zero rows in `doc_symbols.attributes` corpus-wide
/// (`@Environment`, `@SceneStorage`, `@ScaledMetric`, `@FetchRequest`,
/// `@SectionedFetchRequest`, `@ObservationIgnored`,
/// `@ObservationTracked`, `@Sendable`, `@Attribute`, `@Relationship`,
/// the four `@Focused*` wrappers) are intentionally absent from
/// this table; the WHERE clause filters them out before the boost
/// can fire, so an entry would be dead weight.
///
/// Future-maintainer note: after a corpus refresh (v1.3+ release
/// bundle), re-measure the per-wrapper framework distribution with:
/// ```
/// SELECT m.framework, COUNT(*) FROM doc_symbols s
///   JOIN docs_metadata m ON s.doc_uri = m.uri
///   WHERE (',' || s.attributes || ',') LIKE '%,@<Wrapper>,%'
///   GROUP BY m.framework ORDER BY 2 DESC LIMIT 5;
/// ```
/// for each currently-absent wrapper, plus the 16 already in the
/// table. Add an entry for a previously-absent wrapper when the
/// rank-1 framework row-count exceeds ~50 (below that, alphabetic
/// noise dominates the boost signal anyway). Repoint an existing
/// entry when the rank-1 framework changes by more than a 2x
/// factor relative to the entry's current target set.
private let propertyWrapperCanonicalFrameworks: [String: Set<String>] = [
    // SwiftUI-declared, SwiftUI-used (boost direction matches).
    "state": ["swiftui"],
    "binding": ["swiftui"],
    "stateobject": ["swiftui"],
    "observedobject": ["swiftui"],
    "environmentobject": ["swiftui"],
    "appstorage": ["swiftui"],
    "focusstate": ["swiftui"],
    "gesturestate": ["swiftui"],
    "namespace": ["swiftui"],
    // Observation-declared, SwiftUI-used (declaration ≠ usage).
    "observable": ["swiftui"],
    // Combine-declared, SwiftUI-used (declaration ≠ usage; SwiftUI
    // ViewModels apply @Published far more often than Combine's
    // own docs demonstrate it).
    "published": ["swiftui"],
    // SwiftData-declared, SwiftUI-used (SwiftData @Model / @Query
    // usages live in SwiftUI sample-code apps that bind a
    // SwiftData model into a View).
    "model": ["swiftui"],
    "query": ["swiftui"],
    // Swift standard-library, used across the Apple SDK fleet.
    // @MainActor has 988 / 915 / 753 / 713 rows in the four
    // umbrella UI frameworks; the boost matches the set rather
    // than the declaration framework.
    "mainactor": ["uikit", "swiftui", "appkit", "realitykit"],
    // Swift standard-library, declared + used in the swift
    // framework's own pages. Small (4 / 1 rows) but the boost
    // direction matches.
    "tasklocal": ["swift"],
    "globalactor": ["swift"],
]

/// #670 — variant of `signalRankOrderClause` with an additional
/// tier between kind-shape and `s.name` that boosts rows whose
/// symbol name exactly equals the query string (case-insensitive).
///
/// Pre-#670 fix, `searchSymbols(query: "Task")` matched on
/// `s.name LIKE '%Task%'`, then ranked by kind tier + alphabetic
/// `s.name`. Among `kind=class` rows, `AVAggregateAssetDownloadTask`
/// beat the canonical `Task` (struct) because the struct's kind tier
/// is 0 and the AV* class's tier is 0 too — both share tier 0, so
/// alphabetic order put AV* first.
///
/// The new tier promotes any row whose `LOWER(s.name) = LOWER(query)`
/// to position 0 within its kind-shape bucket. `Task` (struct) and
/// `AVAggregateAssetDownloadTask` (class) share kind tier 0; the
/// exact-name match `Task` wins tier-3 (0 < 1), so it lands first.
/// Substring matches keep their relative alphabetic ordering inside
/// tier-3 = 1.
///
/// Only `searchSymbols` benefits from this — the other 3 AST
/// queries match on attributes / conformances, not symbol name, so
/// they continue to use the original `signalRankOrderClause`.
private let signalRankOrderClauseWithExactName = """
ORDER BY
    CASE WHEN s.name IN (
        '==(_:_:)', '!=(_:_:)', '<(_:_:)', '<=(_:_:)', '>(_:_:)', '>=(_:_:)',
        '~=(_:_:)', 'hash(into:)',
        '==', '!=', '<', '<=', '>', '>='
    ) THEN 1 ELSE 0 END,
    CASE
        WHEN s.kind IN ('class', 'struct', 'enum', 'protocol', 'actor') THEN 0
        WHEN s.kind IN ('typealias', 'macro') THEN 1
        WHEN s.kind IN ('method', 'function', 'property', 'initializer', 'subscript', 'case') THEN 2
        WHEN s.kind = 'operator' THEN 3
        ELSE 4
    END,
    CASE WHEN LOWER(s.name) = LOWER(?) THEN 0 ELSE 1 END,
    s.name
"""

extension Search.Index {
    public func searchSymbols(
        query: String?,
        kind: String? = nil,
        isAsync: Bool? = nil,
        framework: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        var conditions: [String] = []
        var params: [Any] = []

        if let query, !query.isEmpty {
            conditions.append("s.name LIKE ?")
            params.append("%\(query)%")
        }

        if let kind, !kind.isEmpty {
            conditions.append("s.kind = ?")
            params.append(kind.lowercased())
        }

        if let isAsync, isAsync {
            conditions.append("s.is_async = 1")
        }

        if let framework, !framework.isEmpty {
            conditions.append("m.framework = ?")
            params.append(framework.lowercased())
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        // #670 — promote exact-name matches above substring matches
        // within the same kind tier when a query string was supplied.
        // The variant clause adds one extra `?` placeholder bound to
        // the query string between the WHERE params and the LIMIT.
        let hasQueryForExactMatch = query?.isEmpty == false
        let orderByClause = hasQueryForExactMatch ? signalRankOrderClauseWithExactName : signalRankOrderClause

        let sql = """
        SELECT DISTINCT
            s.doc_uri,
            f.title,
            COALESCE(m.framework, '') as framework,
            s.name,
            s.kind,
            s.signature,
            s.attributes,
            s.conformances,
            s.is_async,
            s.is_public
        FROM doc_symbols s
        JOIN docs_fts f ON s.doc_uri = f.uri
        LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
        \(whereClause)
        \(orderByClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Symbol search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            if let str = param as? String {
                sqlite3_bind_text(statement, paramIndex, (str as NSString).utf8String, -1, nil)
            }
            paramIndex += 1
        }
        // #670 — bind exact-name ORDER BY placeholder between WHERE params and LIMIT.
        if let query, !query.isEmpty {
            sqlite3_bind_text(statement, paramIndex, (query as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let isAsync = sqlite3_column_int(statement, 8) != 0
            let isPublic = sqlite3_column_int(statement, 9) != 0

            results.append(Search.SymbolSearchResult(
                docUri: docUri,
                docTitle: docTitle,
                framework: framework,
                symbolName: symbolName,
                symbolKind: symbolKind,
                signature: signature,
                attributes: attributes,
                conformances: conformances,
                isAsync: isAsync,
                isPublic: isPublic
            ))
        }

        return results
    }

    /// Search for property wrapper usage
    /// - Parameters:
    ///   - wrapper: Property wrapper name (with or without @)
    ///   - framework: Filter by framework
    ///   - limit: Maximum results
    /// - Returns: Array of symbol results containing the wrapper
    public func searchPropertyWrappers(
        wrapper: String,
        framework: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Normalize wrapper name (add @ if not present). Strip the
        // leading `@` for the canonical-framework lookup; the
        // attribute-column LIKE pattern keeps it.
        let normalizedWrapper = wrapper.hasPrefix("@") ? wrapper : "@\(wrapper)"
        let unprefixedWrapper = normalizedWrapper.hasPrefix("@")
            ? String(normalizedWrapper.dropFirst())
            : normalizedWrapper

        // #952: precision attribute match. Pre-#952 used
        // `s.attributes LIKE '%@State%'` which also matched
        // `@StateObject` (21 false-positive rows in the v1.2.x
        // bundle). The wrapped form
        // `(',' || s.attributes || ',') LIKE '%,@State,%'` matches
        // the `@State` token only when it is bounded by commas on
        // both sides; the wrapping ensures the boundary holds for
        // single-attribute rows, leading-attribute rows, and
        // trailing-attribute rows alike.
        let precisePattern = "%,\(normalizedWrapper),%"

        var conditions = ["(',' || s.attributes || ',') LIKE ?"]
        var params: [String] = [precisePattern]

        if let framework, !framework.isEmpty {
            conditions.append("m.framework = ?")
            params.append(framework.lowercased())
        }

        let whereClause = "WHERE " + conditions.joined(separator: " AND ")

        // #952: canonical-framework boost. If the queried wrapper
        // has a known home framework, prefix the shared
        // `signalRankOrderClause` with a tier-0 boost so rows in
        // the canonical framework rank above all others. The boost
        // is conditional, not unconditional: if a row's framework
        // is null OR not in the canonical set, it falls through to
        // the operator-demote / kind-shape tiers as before.
        let canonicalFrameworks = propertyWrapperCanonicalFrameworks[unprefixedWrapper.lowercased()]
        let orderByClause: String
        if let canonicalFrameworks, !canonicalFrameworks.isEmpty {
            let placeholders = canonicalFrameworks.map { _ in "?" }.joined(separator: ", ")
            // Splice the canonical-framework boost as the FIRST
            // tier of the ORDER BY by extracting the shared
            // clause's body and prepending the new tier. The
            // shared clause already begins with `ORDER BY`, so
            // we strip that prefix once and rejoin.
            //
            // Structural dependency: `signalRankOrderClause` must
            // begin with the literal byte sequence `ORDER BY\n`.
            // The one-shot `signalRankOrderClausePrefixCheck`
            // file-scope constant asserts this once per process in
            // debug builds (referenced here for evaluation order);
            // release builds rely on the empirical test coverage at
            // `Issue952PropertyWrapperRankingTests` to catch any
            // drift via the thrown `Search.Error.searchFailed`
            // from `sqlite3_prepare_v2`.
            _ = signalRankOrderClausePrefixCheck
            let sharedBody = signalRankOrderClause
                .replacingOccurrences(of: "ORDER BY\n", with: "")
            orderByClause = """
            ORDER BY
                CASE WHEN LOWER(m.framework) IN (\(placeholders)) THEN 0 ELSE 1 END,
                \(sharedBody)
            """
            for fw in canonicalFrameworks.sorted() {
                params.append(fw)
            }
        } else {
            orderByClause = signalRankOrderClause
        }

        let sql = """
        SELECT DISTINCT
            s.doc_uri,
            f.title,
            COALESCE(m.framework, '') as framework,
            s.name,
            s.kind,
            s.signature,
            s.attributes,
            s.conformances,
            s.is_async,
            s.is_public
        FROM doc_symbols s
        JOIN docs_fts f ON s.doc_uri = f.uri
        LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
        \(whereClause)
        \(orderByClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Property wrapper search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let isAsync = sqlite3_column_int(statement, 8) != 0
            let isPublic = sqlite3_column_int(statement, 9) != 0

            results.append(Search.SymbolSearchResult(
                docUri: docUri,
                docTitle: docTitle,
                framework: framework,
                symbolName: symbolName,
                symbolKind: symbolKind,
                signature: signature,
                attributes: attributes,
                conformances: conformances,
                isAsync: isAsync,
                isPublic: isPublic
            ))
        }

        return results
    }

    /// Search for concurrency patterns (async, actor, sendable, mainactor)
    /// - Parameters:
    ///   - pattern: Concurrency pattern to search for
    ///   - framework: Filter by framework
    ///   - limit: Maximum results
    /// - Returns: Array of matching symbol results
    public func searchConcurrencyPatterns(
        pattern: String,
        framework: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        var conditions: [String] = []
        var params: [String] = []

        // Map pattern to appropriate query
        switch pattern.lowercased() {
        case "async":
            conditions.append("s.is_async = 1")
        case "actor":
            conditions.append("s.kind = 'actor'")
        case "sendable":
            conditions.append("s.conformances LIKE '%Sendable%'")
        case "mainactor":
            conditions.append("s.attributes LIKE '%@MainActor%'")
        case "task":
            conditions.append("(s.name LIKE '%Task%' OR s.signature LIKE '%Task%')")
        case "asyncsequence":
            conditions.append("s.conformances LIKE '%AsyncSequence%'")
        default:
            // Generic search in attributes and conformances
            conditions.append("(s.attributes LIKE ? OR s.conformances LIKE ? OR s.signature LIKE ?)")
            let likePattern = "%\(pattern)%"
            params.append(likePattern)
            params.append(likePattern)
            params.append(likePattern)
        }

        if let framework, !framework.isEmpty {
            conditions.append("m.framework = ?")
            params.append(framework.lowercased())
        }

        let whereClause = "WHERE " + conditions.joined(separator: " AND ")

        let sql = """
        SELECT DISTINCT
            s.doc_uri,
            f.title,
            COALESCE(m.framework, '') as framework,
            s.name,
            s.kind,
            s.signature,
            s.attributes,
            s.conformances,
            s.is_async,
            s.is_public
        FROM doc_symbols s
        JOIN docs_fts f ON s.doc_uri = f.uri
        LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
        \(whereClause)
        \(signalRankOrderClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Concurrency pattern search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let isAsync = sqlite3_column_int(statement, 8) != 0
            let isPublic = sqlite3_column_int(statement, 9) != 0

            results.append(Search.SymbolSearchResult(
                docUri: docUri,
                docTitle: docTitle,
                framework: framework,
                symbolName: symbolName,
                symbolKind: symbolKind,
                signature: signature,
                attributes: attributes,
                conformances: conformances,
                isAsync: isAsync,
                isPublic: isPublic
            ))
        }

        return results
    }

    /// Search for types by protocol conformance
    /// - Parameters:
    ///   - protocolName: Protocol name to search for
    ///   - framework: Filter by framework
    ///   - limit: Maximum results
    /// - Returns: Array of symbol results conforming to the protocol
    public func searchConformances(
        protocolName: String,
        framework: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let conformancePattern = "%\(protocolName)%"

        var conditions = ["s.conformances LIKE ?"]
        var params: [String] = [conformancePattern]

        if let framework, !framework.isEmpty {
            conditions.append("m.framework = ?")
            params.append(framework.lowercased())
        }

        let whereClause = "WHERE " + conditions.joined(separator: " AND ")

        let sql = """
        SELECT DISTINCT
            s.doc_uri,
            f.title,
            COALESCE(m.framework, '') as framework,
            s.name,
            s.kind,
            s.signature,
            s.attributes,
            s.conformances,
            s.is_async,
            s.is_public
        FROM doc_symbols s
        JOIN docs_fts f ON s.doc_uri = f.uri
        LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
        \(whereClause)
        \(signalRankOrderClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Conformance search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let isAsync = sqlite3_column_int(statement, 8) != 0
            let isPublic = sqlite3_column_int(statement, 9) != 0

            results.append(Search.SymbolSearchResult(
                docUri: docUri,
                docTitle: docTitle,
                framework: framework,
                symbolName: symbolName,
                symbolKind: symbolKind,
                signature: signature,
                attributes: attributes,
                conformances: conformances,
                isAsync: isAsync,
                isPublic: isPublic
            ))
        }

        return results
    }

    /// Search for generic types / functions by constraint.
    ///
    /// Layer 2 of #409 (issue #665). Surfaces the
    /// `doc_symbols.generic_constraints` column (e.g. `Collection`,
    /// `Hashable & Sendable`) populated at index time from two
    /// sources per #755: (a) the AST extractor's `T: Collection`
    /// form, split into name + constraint and the constraint half
    /// written here; (b) `where`-clause patterns regex-parsed from
    /// the `signature` column. Match is substring-LIKE so a query of
    /// `Sendable` returns both `Sendable` and `Hashable & Sendable`.
    ///
    /// Pre-#755 this column was named `generic_params` and held
    /// type-parameter names, not constraints — the search advertised
    /// constraint match but the corpus carried only 17 rows of
    /// constraint-form data out of 351,495 because most Apple HTML
    /// snippets carry bare `<T>` declarations. The schema-v17
    /// migration adds `generic_constraints`; the column is populated
    /// by the next `cupertino save --docs` re-index.
    ///
    /// Mirrors `searchConformances`: same WHERE/ORDER/LIMIT shape,
    /// same `Search.SymbolSearchResult` return type, but populates
    /// `genericParams` on the result so the MCP layer can echo what
    /// matched (the param-name column carries the AST extractor's
    /// own name half and remains useful for that surface).
    ///
    /// - Parameters:
    ///   - constraint: Generic constraint to search for (substring).
    ///   - framework: Filter by framework.
    ///   - limit: Maximum results.
    /// - Returns: Symbols whose `generic_constraints` contains the
    ///   constraint substring.
    public func searchByGenericConstraint(
        constraint: String,
        framework: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) async throws -> [Search.SymbolSearchResult] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let constraintPattern = "%\(constraint)%"

        var conditions = ["s.generic_constraints LIKE ?"]
        var params: [String] = [constraintPattern]

        if let framework, !framework.isEmpty {
            conditions.append("m.framework = ?")
            params.append(framework.lowercased())
        }

        let whereClause = "WHERE " + conditions.joined(separator: " AND ")

        let sql = """
        SELECT DISTINCT
            s.doc_uri,
            f.title,
            COALESCE(m.framework, '') as framework,
            s.name,
            s.kind,
            s.signature,
            s.attributes,
            s.conformances,
            s.is_async,
            s.is_public,
            s.generic_params
        FROM doc_symbols s
        JOIN docs_fts f ON s.doc_uri = f.uri
        LEFT JOIN docs_metadata m ON s.doc_uri = m.uri
        \(whereClause)
        \(signalRankOrderClause)
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Generic-constraint search failed: \(errorMessage)")
        }

        var paramIndex: Int32 = 1
        for param in params {
            sqlite3_bind_text(statement, paramIndex, (param as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        var results: [Search.SymbolSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let docUri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let docTitle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let symbolName = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let symbolKind = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let signature = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            let attributes = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let conformances = sqlite3_column_text(statement, 7).map { String(cString: $0) }
            let isAsync = sqlite3_column_int(statement, 8) != 0
            let isPublic = sqlite3_column_int(statement, 9) != 0
            let genericParams = sqlite3_column_text(statement, 10).map { String(cString: $0) }

            results.append(Search.SymbolSearchResult(
                docUri: docUri,
                docTitle: docTitle,
                framework: framework,
                symbolName: symbolName,
                symbolKind: symbolKind,
                signature: signature,
                attributes: attributes,
                conformances: conformances,
                isAsync: isAsync,
                isPublic: isPublic,
                genericParams: genericParams
            ))
        }

        return results
    }

    // Get total symbol count in database
}
