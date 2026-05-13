import Foundation
import SharedConstants
import SharedCore
import SearchRanking
import SQLite3

// swiftlint:disable function_body_length file_length
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

extension Search.Index {
    /// Search documents by query with optional source, framework, and language filters.
    /// If query starts with a known source prefix (e.g., "swift-book"), it's extracted as a filter.
    /// - Parameters:
    ///   - query: Search query (may include source prefix like "swift-evolution actors")
    ///   - source: Optional source filter (apple-docs, swift-evolution, etc.)
    ///   - framework: Optional framework filter (swiftui, foundation, etc. - only for apple-docs)
    ///   - language: Optional language filter (swift, objc)
    ///   - limit: Maximum number of results
    // swiftlint:disable:next cyclomatic_complexity
    public func search(
        query: String,
        source: String? = nil,
        framework: String? = nil,
        language: String? = nil,
        limit: Int = Shared.Constants.Limit.defaultSearchLimit,
        includeArchive: Bool = false,
        minIOS: String? = nil,
        minMacOS: String? = nil,
        minTvOS: String? = nil,
        minWatchOS: String? = nil,
        minVisionOS: String? = nil
    ) async throws -> [Search.Result] {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Search.Error.invalidQuery("Query cannot be empty")
        }

        // Detect query intent for source boosting (#81)
        // This analyzes the query to determine what kind of content the user wants
        let queryIntent = detectQueryIntent(query)

        // Extract source prefix from query if no explicit source provided
        let (detectedSource, remainingQuery) = source == nil
            ? extractSourcePrefix(query)
            : (nil, query)

        // Use explicit source or detected source
        let effectiveSource = source ?? detectedSource

        // Resolve framework input to identifier (supports "appintents", "AppIntents", "App Intents")
        let effectiveFramework: String?
        if let framework {
            effectiveFramework = try await resolveFrameworkIdentifier(framework)
        } else {
            effectiveFramework = nil
        }

        // Check if user explicitly requested archive
        let archiveRequested = effectiveSource == "apple-archive"

        // Use remaining query after extracting source prefix
        let queryToSearch = remainingQuery.isEmpty ? query : remainingQuery

        // Extract @attribute patterns from query (handles "@MainActor" and "MainActor")
        // Note: Attributes are used for boosting via symbol search, not hard filtering
        let (_, queryForFTS) = extractAttributeFilters(queryToSearch)
        let sanitizedQuery = sanitizeFTS5Query(queryForFTS)

        // Per-column bm25 weights (#181, #192 D): title dominates, symbols next,
        // summary third, framework modest bonus. Body matches are common and
        // easily dilute ranking; title and AST-derived symbols are the user's
        // clearest intent signal. Column order matches the docs_fts
        // declaration: uri, source, framework, language, title, content,
        // summary, symbols.
        //
        // Rationale for symbols=5.0: code-derived names ("Observable", "Task",
        // "@MainActor") are strong signals but slightly below a title-level
        // match. Placed above summary (3.0) since semantic queries target
        // type names directly; below title (10.0) since a user typing
        // "Task" still wants the Swift Task struct first, not any doc that
        // mentions it in a code block.
        var sql = """
        SELECT
            f.uri,
            f.source,
            f.framework,
            f.title,
            f.summary,
            m.file_path,
            m.word_count,
            bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0) as rank,
            COALESCE(s.kind, 'unknown') as kind,
            m.min_ios,
            m.min_macos,
            m.min_tvos,
            m.min_watchos,
            m.min_visionos
        FROM docs_fts f
        JOIN docs_metadata m ON f.uri = m.uri
        LEFT JOIN docs_structured s ON f.uri = s.uri
        WHERE docs_fts MATCH ?
        """

        if effectiveSource != nil {
            sql += " AND f.source = ?"
        } else if !includeArchive, !archiveRequested {
            // Exclude apple-archive by default unless explicitly requested or includeArchive is true
            sql += " AND f.source != 'apple-archive'"
        }
        if effectiveFramework != nil {
            sql += " AND f.framework = ?"
        }
        if language != nil {
            sql += " AND f.language = ?"
        }

        // Note: Attribute patterns (e.g., "@MainActor") are used for BOOSTING via symbol search,
        // not hard filtering. Hard filtering would return 0 results for macros like @Observable
        // that aren't in doc_symbols.attributes. Symbol boosting happens later in this function.

        // Normalize empty strings to nil (treat as no filter)
        let effectiveMinIOS = minIOS?.isEmpty == true ? nil : minIOS
        let effectiveMinMacOS = minMacOS?.isEmpty == true ? nil : minMacOS
        let effectiveMinTvOS = minTvOS?.isEmpty == true ? nil : minTvOS
        let effectiveMinWatchOS = minWatchOS?.isEmpty == true ? nil : minWatchOS
        let effectiveMinVisionOS = minVisionOS?.isEmpty == true ? nil : minVisionOS

        // Add platform version filters (uses indexed columns for NULL filtering)
        // Note: We filter IS NOT NULL at SQL level (uses index), then do proper
        // version comparison in memory since SQL CAST doesn't handle "10.13" vs "10.2" correctly
        if effectiveMinIOS != nil {
            sql += " AND m.min_ios IS NOT NULL"
        }
        if effectiveMinMacOS != nil {
            sql += " AND m.min_macos IS NOT NULL"
        }
        if effectiveMinTvOS != nil {
            sql += " AND m.min_tvos IS NOT NULL"
        }
        if effectiveMinWatchOS != nil {
            sql += " AND m.min_watchos IS NOT NULL"
        }
        if effectiveMinVisionOS != nil {
            sql += " AND m.min_visionos IS NOT NULL"
        }

        // Fetch significantly more results so title/kind boosts can surface buried gems.
        // BM25 alone buries canonical type pages whose title carries Apple's
        // " | Apple Developer Documentation" suffix (e.g. Swift `Task` struct
        // lands around raw rank 241 for query "Task" because field-length
        // normalization punishes the diluted title). The post-rank
        // multipliers can pull such pages to #1, but only if they're in
        // the candidate set. Floor at 1000 so smart-query fan-out (which
        // passes limit=10) still over-fetches enough to include them.
        let fetchLimit = min(max(limit * 20, 1000), 2000)
        sql += " ORDER BY rank LIMIT ?;"

        // Pre-calculate query words for ranking heuristics (#81)
        let queryWords = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0.count > 1 } // Filter noise words

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Prepare failed: \(errorMessage)")
        }

        // Bind parameters (use sanitized query for FTS5)
        var paramIndex: Int32 = 1
        sqlite3_bind_text(statement, paramIndex, (sanitizedQuery as NSString).utf8String, -1, nil)
        paramIndex += 1

        if let effectiveSource {
            sqlite3_bind_text(statement, paramIndex, (effectiveSource as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        if let effectiveFramework {
            sqlite3_bind_text(statement, paramIndex, (effectiveFramework as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        if let language {
            sqlite3_bind_text(statement, paramIndex, (language as NSString).utf8String, -1, nil)
            paramIndex += 1
        }
        // Note: Attribute filters removed - boosting via symbol search instead
        // Note: Platform version filters use IS NOT NULL (no binding needed)
        // Proper version comparison happens in memory after fetch
        sqlite3_bind_int(statement, paramIndex, Int32(fetchLimit))

        // Execute and collect results
        // Column order: uri(0), source(1), framework(2), title(3), summary(4), file_path(5),
        //               word_count(6), rank(7), kind(8), min_ios(9), min_macos(10),
        //               min_tvos(11), min_watchos(12), min_visionos(13)
        var results: [Search.Result] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uriPtr = sqlite3_column_text(statement, 0),
                  let sourcePtr = sqlite3_column_text(statement, 1),
                  let frameworkPtr = sqlite3_column_text(statement, 2),
                  let titlePtr = sqlite3_column_text(statement, 3),
                  let summaryPtr = sqlite3_column_text(statement, 4),
                  let filePathPtr = sqlite3_column_text(statement, 5),
                  let kindPtr = sqlite3_column_text(statement, 8)
            else {
                continue
            }

            let uri = String(cString: uriPtr)
            let source = String(cString: sourcePtr)
            let framework = String(cString: frameworkPtr)
            let title = String(cString: titlePtr)
            let summary = String(cString: summaryPtr)
            let filePath = String(cString: filePathPtr)
            let wordCount = Int(sqlite3_column_int(statement, 6))
            let bm25Rank = sqlite3_column_double(statement, 7)

            // Read availability from dedicated columns (no JSON parsing needed)
            let miniOSPtr = sqlite3_column_text(statement, 9)
            let minMacOSPtr = sqlite3_column_text(statement, 10)
            let minTvOSPtr = sqlite3_column_text(statement, 11)
            let minWatchOSPtr = sqlite3_column_text(statement, 12)
            let minVisionOSPtr = sqlite3_column_text(statement, 13)

            // Build availability array from columns
            var availabilityItems: [Search.PlatformAvailability] = []
            if let ptr = miniOSPtr {
                availabilityItems.append(Search.PlatformAvailability(
                    name: "iOS",
                    introducedAt: String(cString: ptr),
                    deprecated: false,
                    unavailable: false,
                    beta: false
                ))
            }
            if let ptr = minMacOSPtr {
                availabilityItems.append(Search.PlatformAvailability(
                    name: "macOS",
                    introducedAt: String(cString: ptr),
                    deprecated: false,
                    unavailable: false,
                    beta: false
                ))
            }
            if let ptr = minTvOSPtr {
                availabilityItems.append(Search.PlatformAvailability(
                    name: "tvOS",
                    introducedAt: String(cString: ptr),
                    deprecated: false,
                    unavailable: false,
                    beta: false
                ))
            }
            if let ptr = minWatchOSPtr {
                availabilityItems.append(Search.PlatformAvailability(
                    name: "watchOS",
                    introducedAt: String(cString: ptr),
                    deprecated: false,
                    unavailable: false,
                    beta: false
                ))
            }
            if let ptr = minVisionOSPtr {
                availabilityItems.append(Search.PlatformAvailability(
                    name: "visionOS",
                    introducedAt: String(cString: ptr),
                    deprecated: false,
                    unavailable: false,
                    beta: false
                ))
            }
            let availability: [Search.PlatformAvailability]? = availabilityItems.isEmpty ? nil : availabilityItems
            let rawKind = String(cString: kindPtr)

            // Infer kind when unknown using multiple signals
            let kind: String = {
                if rawKind != "unknown" && !rawKind.isEmpty {
                    return rawKind
                }

                // SIGNAL 1: URL depth analysis
                // Shallow paths like /documentation/swiftui/view → core type
                // Deep paths like /documentation/swiftui/view/body-8kl5o → member
                let pathComponents = uri.components(separatedBy: "/")
                    .filter { !$0.isEmpty && $0 != "documentation" }
                let urlDepth = pathComponents.count

                // SIGNAL 2: Title pattern analysis
                let titleLower = title.lowercased()
                let titleTrimmed = title.trimmingCharacters(in: .whitespaces)

                // Method patterns: contains parentheses like foo(_:) or init(from:)
                if title.contains("(_:") || title.contains("(") && title.contains(":)") {
                    return "method"
                }

                // Operator patterns: starts with operator symbols
                if titleTrimmed.hasPrefix("+") || titleTrimmed.hasPrefix("-") ||
                    titleTrimmed.hasPrefix("*") || titleTrimmed.hasPrefix("/") ||
                    titleTrimmed.hasPrefix("==") || titleTrimmed.hasPrefix("!=") ||
                    titleTrimmed.hasPrefix("<") || titleTrimmed.hasPrefix(">") {
                    return "method" // Operators are methods
                }

                // Property patterns: camelCase starting lowercase, single word
                let words = title.components(separatedBy: .whitespaces)
                if words.count == 1 {
                    let first = titleTrimmed.first
                    if let first, first.isLowercase, !title.contains("(") {
                        return "property"
                    }
                }

                // Protocol suffix pattern
                if titleLower.hasSuffix("protocol") || titleLower.hasSuffix("delegate") {
                    return "protocol"
                }

                // SIGNAL 3: URL depth heuristic for Apple docs
                // /framework/type → depth 2 = core type
                // /framework/type/member → depth 3+ = member
                if uri.hasPrefix("apple-docs://") {
                    if urlDepth <= 2 {
                        // Short path + CamelCase title = likely core type
                        if let first = titleTrimmed.first, first.isUppercase, !title.contains("(") {
                            return "struct" // Default to struct for unknown core types
                        }
                    } else if urlDepth >= 3 {
                        // Deep path = likely member
                        if let first = titleTrimmed.first, first.isLowercase {
                            return "property"
                        }
                    }
                }

                // SIGNAL 4: Word count as quality signal
                // Core types typically have rich documentation
                if wordCount > 500, urlDepth <= 2 {
                    if let first = titleTrimmed.first, first.isUppercase {
                        return "struct" // Rich docs + short path + CamelCase = core type
                    }
                }

                return "unknown"
            }()

            // Apply kind-based ranking multiplier
            let kindMultiplier = self.kindMultiplier(for: kind)

            // Apply source-based ranking multiplier with intent-aware boosting (#81)
            let sourceMultiplier = self.sourceMultiplier(for: source, uri: uri, queryIntent: queryIntent)

            // Apply intelligent title and query matching heuristics
            let combinedBoost = self.combinedBoost(
                uri: uri,
                query: query,
                queryWords: queryWords,
                title: title,
                kind: kind,
                framework: framework
            )

            // Calculate final adjusted rank
            let adjustedRank = Self.computeRank(
                bm25Rank: bm25Rank,
                kindMultiplier: kindMultiplier,
                sourceMultiplier: sourceMultiplier,
                combinedBoost: combinedBoost
            )

            results.append(
                Search.Result(
                    uri: uri,
                    source: source,
                    framework: framework,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: adjustedRank,
                    availability: availability
                )
            )
        }

        // Re-sort by adjusted rank (lower BM25 = better)
        results.sort { $0.rank < $1.rank }

        // (#81) Boost results that also match in doc_symbols_fts
        // This enables semantic search for @Observable, async, Sendable, etc.
        let symbolMatchURIs = try await searchSymbolsForURIs(query: sanitizedQuery, limit: 500)
        if !symbolMatchURIs.isEmpty {
            results = self.boostSymbolMatches(results: results, symbolMatchURIs: symbolMatchURIs)
            // Re-sort after symbol boosting
            results.sort { $0.rank < $1.rank }
        }

        // Apply platform version filters (proper semantic version comparison)
        // SQL already filtered for IS NOT NULL, now we do proper version compare
        results = self.filterByPlatformAvailability(
            results: results,
            minIOS: effectiveMinIOS,
            minMacOS: effectiveMinMacOS,
            minTvOS: effectiveMinTvOS,
            minWatchOS: effectiveMinWatchOS,
            minVisionOS: effectiveMinVisionOS
        )

        // (#81 & #256) Ensure framework root and canonical type pages appear at top
        results = try await self.forceIncludeCanonicalPages(
            results: results,
            query: query,
            effectiveSource: effectiveSource
        )

        // (#81) Attach matching symbols to results that have them
        if !symbolMatchURIs.isEmpty {
            let symbolsByURI = try await fetchMatchingSymbols(query: sanitizedQuery, uris: symbolMatchURIs)
            results = results.map { result in
                if let symbols = symbolsByURI[result.uri], !symbols.isEmpty {
                    return Search.Result(
                        id: result.id,
                        uri: result.uri,
                        source: result.source,
                        framework: result.framework,
                        title: result.title,
                        summary: result.summary,
                        filePath: result.filePath,
                        wordCount: result.wordCount,
                        rank: result.rank,
                        availability: result.availability,
                        matchedSymbols: symbols
                    )
                }
                return result
            }
        }

        // Trim to requested limit after applying boosts
        return Array(results.prefix(limit))
    }

    /// Fetch matching symbols for a set of document URIs (#81)
    /// Returns dictionary mapping URI to array of matched symbols
    func fetchMatchingSymbols(query: String, uris: Set<String>) async throws -> [String: [Search.MatchedSymbol]] {
        guard let database, !uris.isEmpty else { return [:] }

        // Strip FTS5 quotes from sanitized query for LIKE pattern
        let cleanQuery = query.replacingOccurrences(of: "\"", with: "")
        let likePattern = "%\(cleanQuery)%"

        // Build placeholders for IN clause
        let placeholders = uris.map { _ in "?" }.joined(separator: ", ")
        let sql = """
        SELECT doc_uri, kind, name, signature, is_async
        FROM doc_symbols
        WHERE doc_uri IN (\(placeholders))
          AND (name LIKE ? OR attributes LIKE ? OR conformances LIKE ? OR signature LIKE ?)
        ORDER BY doc_uri, name
        LIMIT 500;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return [:]
        }

        // Bind URI parameters
        var bindIndex: Int32 = 1
        for uri in uris {
            sqlite3_bind_text(statement, bindIndex, (uri as NSString).utf8String, -1, nil)
            bindIndex += 1
        }

        // Bind LIKE patterns
        sqlite3_bind_text(statement, bindIndex, (likePattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, bindIndex + 1, (likePattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, bindIndex + 2, (likePattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, bindIndex + 3, (likePattern as NSString).utf8String, -1, nil)

        var result: [String: [Search.MatchedSymbol]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let uriPtr = sqlite3_column_text(statement, 0),
                  let kindPtr = sqlite3_column_text(statement, 1),
                  let namePtr = sqlite3_column_text(statement, 2) else {
                continue
            }

            let uri = String(cString: uriPtr)
            let kind = String(cString: kindPtr)
            let name = String(cString: namePtr)
            let signature = sqlite3_column_text(statement, 3).map { String(cString: $0) }
            let isAsync = sqlite3_column_int(statement, 4) != 0

            let symbol = Search.MatchedSymbol(kind: kind, name: name, signature: signature, isAsync: isAsync)
            result[uri, default: []].append(symbol)
        }

        // Limit symbols per document to top 3 for readability
        for (uri, symbols) in result {
            result[uri] = Array(symbols.prefix(3))
        }

        return result
    }

    /// Search doc_symbols and return matching document URIs (#81)
    /// Enables semantic search for @Observable, async, Sendable, MainActor, etc.
    func searchSymbolsForURIs(query: String, limit: Int) async throws -> Set<String> {
        guard let database else { return [] }

        // Strip FTS5 quotes and trim whitespace for LIKE pattern
        let cleanQuery = query
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard cleanQuery.count >= 3 else { return [] }

        // Search doc_symbols directly using LIKE patterns
        // Matches in: symbol name, attributes (@Observable), conformances (Sendable), signature (async)
        let likePattern = "%\(cleanQuery)%"
        let sql = """
        SELECT DISTINCT doc_uri
        FROM doc_symbols
        WHERE name LIKE ?
           OR attributes LIKE ?
           OR conformances LIKE ?
           OR signature LIKE ?
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return [] // Fail silently - symbol search is optional enhancement
        }

        sqlite3_bind_text(statement, 1, (likePattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (likePattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (likePattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (likePattern as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(limit))

        var uris: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let uriPtr = sqlite3_column_text(statement, 0) {
                uris.insert(String(cString: uriPtr))
            }
        }

        return uris
    }

    /// Frameworks consulted by `fetchCanonicalTypePages` (#256 follow-on).
    ///
    /// Same set as the top-tier entries in `frameworkAuthority`. Kept
    /// narrow on purpose — adding a framework here is a claim that its
    /// `documentation_FRAMEWORK_TOKEN` page is reliably the canonical
    /// answer when a user types `TOKEN` on its own.
    static let canonicalTypePageFrameworks: [String] = [
        "swift", "swiftui", "foundation",
    ]

    /// Hand-fetch canonical type pages whose URI shape is
    /// `apple-docs://FRAMEWORK/documentation_FRAMEWORK_QUERY` for top-tier
    /// frameworks (#256 follow-on). See call site for rationale.
    ///
    /// Probes one URI per top-tier framework; non-existing rows return
    /// nothing. Returned results carry a guaranteed-top rank so the
    /// caller can dedup-and-prepend them without re-running the post-rank
    /// math. Caller is responsible for not invoking this when the
    /// effective source filter is something other than apple-docs.
    func fetchCanonicalTypePages(query: String) async throws -> [Search.Result] {
        guard let database else { return [] }

        // Same shape constraints as `Search.SmartQuery.isLikelySymbolQuery`:
        // single token, length >= 2, ASCII identifier characters only.
        // Multi-word queries don't have an obvious top-level apple-docs
        // URI to probe and aren't the failure mode this addresses.
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              !trimmed.contains(" "),
              !trimmed.contains("."),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        else {
            return []
        }
        let queryLower = trimmed.lowercased()

        // Query docs_metadata only — its `uri` is a TEXT PRIMARY KEY so the
        // lookup is O(log n) on the implicit unique index. Joining
        // `docs_fts` would force a virtual-table SCAN (FTS5 has no
        // queryable index on `uri`), which costs ~3 s per probe on the
        // v1.0 corpus. Title and summary come from `json_data` via
        // `json_extract`; `abstract` is the structured-page summary in
        // the canonical Apple JSON output.
        let sql = """
        SELECT
            m.uri, m.source, m.framework,
            json_extract(m.json_data, '$.title') AS title,
            json_extract(m.json_data, '$.abstract') AS summary,
            m.file_path, m.word_count,
            m.min_ios, m.min_macos, m.min_tvos, m.min_watchos, m.min_visionos
        FROM docs_metadata m
        WHERE m.uri = ?
        LIMIT 1;
        """

        var hits: [Search.Result] = []
        for framework in Self.canonicalTypePageFrameworks {
            let candidateURI = "apple-docs://\(framework)/documentation_\(framework)_\(queryLower)"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                continue
            }
            sqlite3_bind_text(statement, 1, (candidateURI as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                let uri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let frameworkName = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let title = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let summary = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let wordCount = Int(sqlite3_column_int(statement, 6))

                var availabilityArray: [Search.PlatformAvailability] = []
                if let ios = sqlite3_column_text(statement, 7).map({ String(cString: $0) }) {
                    availabilityArray.append(Search.PlatformAvailability(name: "iOS", introducedAt: ios))
                }
                if let macos = sqlite3_column_text(statement, 8).map({ String(cString: $0) }) {
                    availabilityArray.append(Search.PlatformAvailability(name: "macOS", introducedAt: macos))
                }
                if let tvos = sqlite3_column_text(statement, 9).map({ String(cString: $0) }) {
                    availabilityArray.append(Search.PlatformAvailability(name: "tvOS", introducedAt: tvos))
                }
                if let watchos = sqlite3_column_text(statement, 10).map({ String(cString: $0) }) {
                    availabilityArray.append(Search.PlatformAvailability(name: "watchOS", introducedAt: watchos))
                }
                if let visionos = sqlite3_column_text(statement, 11).map({ String(cString: $0) }) {
                    availabilityArray.append(Search.PlatformAvailability(name: "visionOS", introducedAt: visionos))
                }

                hits.append(Search.Result(
                    uri: uri,
                    source: source,
                    framework: frameworkName.isEmpty ? framework : frameworkName,
                    title: title,
                    summary: summary,
                    filePath: filePath,
                    wordCount: wordCount,
                    rank: -2000.0, // Guaranteed top, ahead of even framework-root rank (-1000)
                    availability: availabilityArray.isEmpty ? nil : availabilityArray
                ))
            }

            sqlite3_finalize(statement)
        }

        return hits
    }

    /// Fetch framework root page by exact query match (#81)
    /// If user searches "SwiftUI", directly fetch apple-docs://swiftui/documentation_swiftui
    /// This ensures framework roots always appear regardless of BM25 score
    func fetchFrameworkRoot(query: String) async throws -> Search.Result? {
        guard let database else { return nil }

        // Only for single-word queries that could be framework names
        let queryLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !queryLower.contains(" "), queryLower.count >= 2 else { return nil }

        // Construct expected framework root URI
        let frameworkRootURI = "apple-docs://\(queryLower)/documentation_\(queryLower)"

        // Direct lookup by URI on docs_metadata's TEXT PRIMARY KEY (O(log n)
        // via the implicit unique index). Joining `docs_fts` would force a
        // virtual-table SCAN — FTS5 has no queryable index on `uri` — which
        // costs ~5 s per call on the v1.0 corpus. Title and summary come
        // from `json_data` via `json_extract`; `abstract` is the
        // structured-page summary in the canonical Apple JSON output.
        let sql = """
        SELECT
            m.uri, m.source, m.framework,
            json_extract(m.json_data, '$.title') AS title,
            json_extract(m.json_data, '$.abstract') AS summary,
            m.file_path, m.word_count,
            m.min_ios, m.min_macos, m.min_tvos, m.min_watchos, m.min_visionos
        FROM docs_metadata m
        WHERE m.uri = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_text(statement, 1, (frameworkRootURI as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil // Framework root not found
        }

        // Extract result
        let uri = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let source = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        let framework = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        let title = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
        let summary = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
        let filePath = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
        let wordCount = Int(sqlite3_column_int(statement, 6))

        // Build availability array from platform versions
        var availabilityArray: [Search.PlatformAvailability] = []
        if let ios = sqlite3_column_text(statement, 7).map({ String(cString: $0) }) {
            availabilityArray.append(Search.PlatformAvailability(name: "iOS", introducedAt: ios))
        }
        if let macos = sqlite3_column_text(statement, 8).map({ String(cString: $0) }) {
            availabilityArray.append(Search.PlatformAvailability(name: "macOS", introducedAt: macos))
        }
        if let tvos = sqlite3_column_text(statement, 9).map({ String(cString: $0) }) {
            availabilityArray.append(Search.PlatformAvailability(name: "tvOS", introducedAt: tvos))
        }
        if let watchos = sqlite3_column_text(statement, 10).map({ String(cString: $0) }) {
            availabilityArray.append(Search.PlatformAvailability(name: "watchOS", introducedAt: watchos))
        }
        if let visionos = sqlite3_column_text(statement, 11).map({ String(cString: $0) }) {
            availabilityArray.append(Search.PlatformAvailability(name: "visionOS", introducedAt: visionos))
        }

        // Return with best possible rank (most negative)
        return Search.Result(
            uri: uri,
            source: source,
            framework: framework.isEmpty ? queryLower : framework,
            title: title,
            summary: summary,
            filePath: filePath,
            wordCount: wordCount,
            rank: -1000.0, // Guaranteed top rank
            availability: availabilityArray.isEmpty ? nil : availabilityArray
        )
    }

    /// Compare semantic version strings (e.g., "10.13" vs "10.2")
    /// Returns true if lhs <= rhs (API introduced at or before target version)
    static func isVersion(_ lhs: String, lessThanOrEqualTo rhs: String) -> Bool {
        let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }

        for idx in 0..<max(lhsComponents.count, rhsComponents.count) {
            let lhsValue = idx < lhsComponents.count ? lhsComponents[idx] : 0
            let rhsValue = idx < rhsComponents.count ? rhsComponents[idx] : 0

            if lhsValue < rhsValue { return true }
            if lhsValue > rhsValue { return false }
        }
        return true // Equal versions
    }

    // MARK: - Semantic Symbol Search (#81)

    /// Symbol search result with document context
    public struct SymbolSearchResult: Sendable {
        public let docUri: String
        public let docTitle: String
        public let framework: String
        public let symbolName: String
        public let symbolKind: String
        public let signature: String?
        public let attributes: String?
        public let conformances: String?
        public let isAsync: Bool
        public let isPublic: Bool
    }

    // Search symbols by name pattern and optional filters
    // - Parameters:
    //   - query: Symbol name pattern (partial match)
    //   - kind: Filter by symbol kind (struct, class, actor, enum, protocol, function, property)
    //   - isAsync: Filter to async functions only
    //   - framework: Filter by framework
    //   - limit: Maximum results
    // - Returns: Array of symbol search results with document context
}
