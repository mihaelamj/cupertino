import Foundation
import SharedConstants
import SharedCore
import SQLite3
import SearchModels

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
            // BM25 scores are NEGATIVE (lower = better match)
            // Core types (protocol, class, struct, framework) get boosted (divide to make smaller/better)
            // Member docs (property, method) get penalized (multiply to make larger/worse)
            let kindMultiplier: Double = {
                switch kind {
                case "protocol", "class", "struct", "framework":
                    return 0.5 // Divide to boost (smaller negative = better rank)
                case "property", "method":
                    return 2.0 // Multiply to penalize (larger negative = worse rank)
                default:
                    return 1.0
                }
            }()

            // Apply source-based ranking multiplier with intent-aware boosting (#81)
            // Uses queryIntent to determine which sources should be prioritized
            typealias SourcePrefix = Shared.Constants.SourcePrefix
            let sourceMultiplier: Double = {
                // Penalize release notes - they match almost every query but rarely what user wants
                if uri.contains("release-notes") {
                    return 2.5 // Strong penalty - release notes pollute general searches
                }

                // Convert source string to Search.Source for intent matching
                let searchSource = Search.Source(rawValue: source)

                // Check if this source is boosted for the detected intent
                let isIntentBoosted = searchSource.map { queryIntent.boostedSources.contains($0) } ?? false

                // Get SourceProperties for quality-based scoring (#81)
                // Uses empirical data from SourceRegistry (single source of truth)
                let sourceProps = searchSource.flatMap { Search.SourceRegistry.properties(for: $0.rawValue) }

                // Calculate base multiplier from SourceProperties or fallback to static values
                let baseMultiplier: Double = {
                    if let props = sourceProps {
                        // Use searchQuality to create multiplier
                        // searchQuality 1.0 → multiplier 0.5 (2x boost)
                        // searchQuality 0.5 → multiplier 1.0 (no boost)
                        // searchQuality 0.0 → multiplier 1.5 (penalty)
                        return 1.5 - (props.searchQuality * 1.0)
                    }
                    // Fallback for unknown sources
                    if source == SourcePrefix.appleDocs {
                        return 1.0 // Baseline - modern docs
                    } else if source == SourcePrefix.appleArchive {
                        return 1.5 // Slight penalty - archived guides
                    } else if source == SourcePrefix.swiftEvolution {
                        return 1.3 // Slight penalty - proposals
                    } else if source == SourcePrefix.swiftBook || source == SourcePrefix.swiftOrg {
                        return 0.9 // Slight boost - official Swift docs
                    } else {
                        return 1.0
                    }
                }()

                // Apply intent-aware scoring using SourceProperties.scoreFor(intent:)
                // This gives a weighted score based on how well the source fits the intent
                let intentScore: Double = {
                    guard let props = sourceProps else { return 1.0 }
                    // scoreFor returns 0.0-1.0, higher = better fit
                    // Convert to multiplier: 1.0 → 0.6 (boost), 0.5 → 0.8, 0.0 → 1.0
                    return 1.0 - (props.scoreFor(intent: queryIntent) * 0.4)
                }()

                // Combine: base quality * intent fit * intent boost
                var multiplier = baseMultiplier * intentScore
                if isIntentBoosted {
                    multiplier *= 0.5 // Additional 2x boost for intent-matched sources
                }
                return multiplier
            }()

            // Apply intelligent title and query matching heuristics
            let combinedBoost: Double = {
                // Use original query for semantic matching (not sanitized)
                let queryWords = query.lowercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty && $0.count > 1 } // Filter noise words

                let titleLower = title.lowercased()
                let titleWords = titleLower.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }

                var boost = 1.0

                // FRAMEWORK ROOT BOOST: Framework root page match (#81)
                // If user types "SwiftUI" and this is the SwiftUI framework page = definitely what they want
                // Framework roots often have title "X | Apple Developer Documentation" and kind "article"
                // Detect by: URI pattern "apple-docs://X/documentation_X" where X matches query
                let queryLowerJoined = queryWords.joined(separator: " ")

                // Extract framework from URI: apple-docs://swiftui/documentation_swiftui → swiftui
                let uriLower = uri.lowercased()
                let isFrameworkRoot: Bool = {
                    // Pattern: apple-docs://FRAMEWORK/documentation_FRAMEWORK
                    if uriLower.hasPrefix("apple-docs://") {
                        let parts = uriLower
                            .replacingOccurrences(of: "apple-docs://", with: "")
                            .components(separatedBy: "/")
                        if parts.count == 2,
                           parts[1] == "documentation_\(parts[0])" {
                            // This is a framework root page, check if query matches
                            return parts[0] == queryLowerJoined
                        }
                    }
                    return false
                }()

                let titleWithoutSuffix = titleLower
                    .replacingOccurrences(of: " | apple developer documentation", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if isFrameworkRoot {
                    boost *= 0.01 // 100x boost for framework root page match
                } else if kind == "framework", titleWithoutSuffix == queryLowerJoined {
                    boost *= 0.05 // 20x boost for explicit framework kind match
                }

                // HEURISTIC 1: Short query exact title match (user knows what they want)
                // "View" searching for "View" protocol = almost certainly what they want.
                //
                // Compare against `titleWithoutSuffix` (boilerplate stripped) so the
                // ~28% of apple-docs pages whose `<title>` includes the
                // " | Apple Developer Documentation" suffix still trigger this boost.
                // Without this, BM25 field-length normalization buries canonical
                // type pages (`Task`, `View`, `URLSession`) under shorter clean-titled
                // siblings (kernel `task_*` C functions, devicemanagement `View`,
                // foundation `urlprotocol/task` property, etc.).
                //
                // The suffix itself is a signal: Apple writes
                // "<canonical type name> | Apple Developer Documentation" only for
                // the parent/landing page of a type. Sub-symbols (properties,
                // methods, nested types) get clean titles. Canonical pages still
                // lose raw BM25 to clean-titled siblings (their suffix dilutes
                // term frequency over field length), so the equal 20x boost here
                // wasn't enough to flip the order. Give canonical pages 50x and
                // clean-titled pages 20x so the canonical answer wins decisively.
                if queryWords.count <= 3, titleWithoutSuffix == queryLowerJoined {
                    if titleLower != titleWithoutSuffix {
                        boost *= 0.02 // 50x boost - canonical Apple-curated page
                    } else {
                        boost *= 0.05 // 20x boost - user typed exact name
                    }

                    // HEURISTIC 1.5: Tiebreak inside exact-title peers (#256)
                    //
                    // After the boost above fires, multiple apple-docs rows can
                    // still tie — `Result` matches Swift's enum, Vision's
                    // associated type ON `VisionRequest`, and Installer JS's
                    // runtime type, and all three carry title "Result".
                    // BM25F then decides among them, and BM25F has no opinion
                    // about which framework is canonical for a bare type name.
                    //
                    // Two orthogonal signals separate canonical from peer:
                    //
                    // (1) URI simplicity. `documentation_FRAMEWORK_QUERY`
                    //     exactly is the framework's top-level type page;
                    //     anything deeper is a sub-symbol whose title happens
                    //     to shadow a top-level type elsewhere.
                    //
                    // (2) Framework authority (`frameworkAuthority` map).
                    //     Only consulted in this narrow branch — exact-title
                    //     match in apple-docs.
                    //
                    // Out of scope: when corpus `kind` extraction improves,
                    // an enum/struct/class/protocol tier slots ahead of these.
                    // Today ~49% of apple-docs rows have kind=unknown
                    // (depending on metadata extraction), so kind alone can't
                    // separate canonical from sub-symbol.
                    if uriLower.hasPrefix("apple-docs://") {
                        let pathPart = uriLower
                            .replacingOccurrences(of: "apple-docs://", with: "")
                        let parts = pathPart.components(separatedBy: "/")
                        if parts.count == 2 {
                            let docPrefix = "documentation_\(parts[0])_"
                            let queryAsIdent = queryLowerJoined
                                .replacingOccurrences(of: " ", with: "")
                            if parts[1].hasPrefix(docPrefix),
                               String(parts[1].dropFirst(docPrefix.count)) == queryAsIdent {
                                boost *= 0.6 // ~1.7x: top-level type page beats sub-symbols
                            }
                        }
                        boost *= Self.frameworkAuthority[framework.lowercased()] ?? 1.0
                    }
                }
                // First word exact match (very strong signal)
                else if !titleWords.isEmpty, !queryWords.isEmpty, titleWords[0] == queryWords[0] {
                    boost *= 0.15 // 6-7x boost - title starts with query word
                }
                // All query words in title
                else if queryWords.allSatisfy({ titleLower.contains($0) }) {
                    boost *= 0.3 // 3x boost - all terms match
                }
                // Any query word in title
                else if queryWords.contains(where: { titleLower.contains($0) }) {
                    boost *= 0.6 // ~1.5x boost - partial match
                }

                // HEURISTIC: Penalize nested types when searching for parent type
                // Problem: "Text" query returns "Text.Scale" before "Text"
                // Reason: "Text.Scale" starts with "Text" and gets the 0.15 boost
                // Solution: If query has no dot but title does, apply penalty
                let queryLower = query.lowercased()
                if !queryLower.contains("."), titleLower.contains(".") {
                    boost *= 2.0 // Penalty: nested types should rank below parent types
                }

                // HEURISTIC 2: Query pattern analysis
                let queryText = query.lowercased()

                // "X protocol" pattern → boost protocols more
                if queryText.contains("protocol"), kind == "protocol" {
                    boost *= 0.4 // Extra 2.5x for protocols when user asks for protocols
                }
                // "X class" pattern → boost classes
                else if queryText.contains("class"), kind == "class" {
                    boost *= 0.4
                }
                // "X struct" pattern → boost structs
                else if queryText.contains("struct"), kind == "struct" {
                    boost *= 0.4
                }

                // HEURISTIC 3: Context-aware kind boosting
                // Single-word queries with framework filter = looking for core type
                if queryWords.count == 1, framework == "swiftui" {
                    switch kind {
                    case "protocol", "class", "struct":
                        boost *= 0.5 // Additional 2x for core types with short queries
                    default:
                        break
                    }
                }

                // HEURISTIC 4: Penalize overly verbose titles for short queries
                // If query is short but title is long, it's probably not what user wants
                if queryWords.count <= 2, title.count > 50 {
                    boost *= 1.3 // Slight penalty for verbose titles vs short queries
                }

                return boost
            }()

            // CRITICAL: BM25 scores are negative, LOWER = better
            // To boost (improve rank), we need to make MORE negative
            // So we DIVIDE by multipliers (smaller multiplier = larger negative number)
            let adjustedRank = bm25Rank / (kindMultiplier * sourceMultiplier * combinedBoost)

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
            results = results.map { result in
                if symbolMatchURIs.contains(result.uri) {
                    // BM25 ranks are negative; lower (more negative) is better.
                    // To make a symbol match rank better, multiply by a value
                    // greater than 1 so the result is more negative. The
                    // previous `* 0.3` made rank LESS negative (demotion),
                    // which silently hurt canonical apple-docs pages whose
                    // AST symbols were indexed in `doc_symbols`. Kernel C
                    // pages have no AST symbols, so they kept their rank
                    // and won the comparison.
                    return Search.Result(
                        id: result.id,
                        uri: result.uri,
                        source: result.source,
                        framework: result.framework,
                        title: result.title,
                        summary: result.summary,
                        filePath: result.filePath,
                        wordCount: result.wordCount,
                        rank: result.rank * 3.0, // 3x boost: more-negative rank
                        availability: result.availability
                    )
                }
                return result
            }
            // Re-sort after symbol boosting
            results.sort { $0.rank < $1.rank }
        }

        // Apply platform version filters (proper semantic version comparison)
        // SQL already filtered for IS NOT NULL, now we do proper version compare
        if let effectiveMinIOS {
            results = results.filter { result in
                guard let version = result.minimumiOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: effectiveMinIOS)
            }
        }
        if let effectiveMinMacOS {
            results = results.filter { result in
                guard let version = result.minimumMacOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: effectiveMinMacOS)
            }
        }
        if let effectiveMinTvOS {
            results = results.filter { result in
                guard let version = result.minimumTvOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: effectiveMinTvOS)
            }
        }
        if let effectiveMinWatchOS {
            results = results.filter { result in
                guard let version = result.minimumWatchOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: effectiveMinWatchOS)
            }
        }
        if let effectiveMinVisionOS {
            results = results.filter { result in
                guard let version = result.minimumVisionOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: effectiveMinVisionOS)
            }
        }

        // (#81) Ensure framework root page appears at top for single-word framework queries
        // This bypasses BM25 limitations for framework names like "SwiftUI", "Foundation", etc.
        // Only apply for apple-docs source or when no source filter is specified
        let shouldFetchFrameworkRoot = effectiveSource == nil ||
            effectiveSource == Shared.Constants.SourcePrefix.appleDocs
        if shouldFetchFrameworkRoot,
           let frameworkRoot = try await fetchFrameworkRoot(query: query) {
            // Remove duplicate if it exists in results
            results.removeAll { $0.uri == frameworkRoot.uri }
            // Insert at top
            results.insert(frameworkRoot, at: 0)
        }

        // (#256 follow-on) Force-include canonical type pages for top-tier frameworks.
        //
        // Plain BM25 buries some canonical type parent pages past the
        // 1000-row fetchLimit (Foundation `URL` lands at raw rank 1017 on
        // the v1.0 corpus, Foundation `Data` and Swift `Identifiable`
        // land past 2500). Once outside the candidate set, no post-rank
        // multiplier can save them. This is a separate problem from
        // ranking inside the set: increasing fetchLimit alone can't fix
        // it without paying a per-query cost on every search.
        //
        // Hand-fetch by URI shape `apple-docs://FRAMEWORK/documentation_FRAMEWORK_QUERY`
        // for the same top-tier frameworks already given a positive
        // `frameworkAuthority` weight (swift, swiftui, foundation). O(1)
        // per probe; three probes per single-token query. Only fires for
        // single-word, ASCII-identifier-shaped queries — same rough
        // shape that HEURISTIC 1 + 1.5 already gate on.
        if shouldFetchFrameworkRoot {
            let canonicals = try await fetchCanonicalTypePages(query: query)
            if !canonicals.isEmpty {
                let canonicalURIs = Set(canonicals.map(\.uri))
                results.removeAll { canonicalURIs.contains($0.uri) }
                // Preserve authority order from `canonicalTypePageFrameworks`
                // (swift > swiftui > foundation) — `fetchCanonicalTypePages`
                // returns hits in that order, so prepend en bloc.
                results.insert(contentsOf: canonicals, at: 0)
            }
        }

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

    // `SymbolSearchResult` lives in SearchModels as `Search.SymbolSearchResult`
    // so consumers (SearchToolProvider, MCP responders) can render symbol
    // hits without importing the Search target. The semantic-search
    // methods below produce values of that lifted type.

    // Search symbols by name pattern and optional filters
    // - Parameters:
    //   - query: Symbol name pattern (partial match)
    //   - kind: Filter by symbol kind (struct, class, actor, enum, protocol, function, property)
    //   - isAsync: Filter to async functions only
    //   - framework: Filter by framework
    //   - limit: Maximum results
    // - Returns: Array of symbol search results with document context
}
