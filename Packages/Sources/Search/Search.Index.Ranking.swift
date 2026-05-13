import Foundation
import SharedConstants
import SearchRanking

extension Search.Index {
    // MARK: - Ranking Heuristics (Phase 2 Extraction)

    /// Calculate kind-based ranking multiplier (Block A)
    func kindMultiplier(for kind: String) -> Double {
        switch kind {
        case "protocol", "class", "struct", "framework":
            return 0.5 // Divide to boost (smaller negative = better rank)
        case "property", "method":
            return 2.0 // Multiply to penalize (larger negative = worse rank)
        default:
            return 1.0
        }
    }

    /// Calculate source-based ranking multiplier with intent-aware boosting (Block B)
    func sourceMultiplier(for source: String, uri: String, queryIntent: Search.QueryIntent) -> Double {
        // Penalize release notes - they match almost every query but rarely what user wants
        if uri.contains("release-notes") {
            return 2.5 // Strong penalty - release notes pollute general searches
        }

        // Convert source string to Search.Source for intent matching
        let searchSource = Search.Source(rawValue: source)

        // Check if this source is boosted for the detected intent
        let isIntentBoosted = searchSource.map { queryIntent.boostedSources.contains($0) } ?? false

        // Get SourceProperties for quality-based scoring (#81)
        let sourceProps = searchSource.flatMap { Search.SourceRegistry.properties(for: $0.rawValue) }

        // Calculate base multiplier from SourceProperties or fallback to static values
        let baseMultiplier: Double = {
            if let props = sourceProps {
                // searchQuality 1.0 → multiplier 0.5 (2x boost)
                // searchQuality 0.5 → multiplier 1.0 (no boost)
                // searchQuality 0.0 → multiplier 1.5 (penalty)
                return 1.5 - (props.searchQuality * 1.0)
            }
            // Fallback for unknown sources
            typealias SourcePrefix = Shared.Constants.SourcePrefix
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
    }

    /// Calculate intelligent title and query matching heuristics (Block C)
    func combinedBoost(
        uri: String,
        query: String,
        queryWords: [String],
        title: String,
        kind: String,
        framework: String
    ) -> Double {
        let titleLower = title.lowercased()
        let titleWords = titleLower.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var boost = 1.0

        // FRAMEWORK ROOT BOOST: Framework root page match (#81)
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

        // HEURISTIC 1: Short query exact title match
        if queryWords.count <= 3, titleWithoutSuffix == queryLowerJoined {
            if titleLower != titleWithoutSuffix {
                boost *= 0.02 // 50x boost - canonical Apple-curated page
            } else {
                boost *= 0.05 // 20x boost - user typed exact name
            }

            // HEURISTIC 1.5: Tiebreak inside exact-title peers
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
                boost *= SearchRanking.frameworkAuthority[framework.lowercased()] ?? 1.0
            }
        }
        // First word exact match
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
        let queryLower = query.lowercased()
        if !queryLower.contains("."), titleLower.contains(".") {
            boost *= 2.0 // Penalty: nested types should rank below parent types
        }

        // HEURISTIC 2: Query pattern analysis
        let queryText = query.lowercased()
        if queryText.contains("protocol"), kind == "protocol" {
            boost *= 0.4 // Extra 2.5x for protocols when user asks for protocols
        }
        else if queryText.contains("class"), kind == "class" {
            boost *= 0.4
        }
        else if queryText.contains("struct"), kind == "struct" {
            boost *= 0.4
        }

        // HEURISTIC 3: Context-aware kind boosting
        if queryWords.count == 1, framework == "swiftui" {
            switch kind {
            case "protocol", "class", "struct":
                boost *= 0.5 // Additional 2x for core types with short queries
            default:
                break
            }
        }

        // HEURISTIC 4: Penalize overly verbose titles for short queries
        if queryWords.count <= 2, title.count > 50 {
            boost *= 1.3 // Slight penalty for verbose titles vs short queries
        }

        return boost
    }

    /// Boost results that also match in doc_symbols_fts (Block D/E)
    func boostSymbolMatches(results: [Search.Result], symbolMatchURIs: Set<String>) -> [Search.Result] {
        guard !symbolMatchURIs.isEmpty else { return results }
        return results.map { result in
            if symbolMatchURIs.contains(result.uri) {
                // BM25 ranks are negative; lower (more negative) is better.
                // To make a symbol match rank better, multiply by a value
                // greater than 1 so the result is more negative.
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
    }

    /// Apply platform version filters (Block E)
    func filterByPlatformAvailability(
        results: [Search.Result],
        minIOS: String?,
        minMacOS: String?,
        minTvOS: String?,
        minWatchOS: String?,
        minVisionOS: String?
    ) -> [Search.Result] {
        var filteredResults = results

        if let minIOS {
            filteredResults = filteredResults.filter { result in
                guard let version = result.minimumiOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: minIOS)
            }
        }
        if let minMacOS {
            filteredResults = filteredResults.filter { result in
                guard let version = result.minimumMacOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: minMacOS)
            }
        }
        if let minTvOS {
            filteredResults = filteredResults.filter { result in
                guard let version = result.minimumTvOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: minTvOS)
            }
        }
        if let minWatchOS {
            filteredResults = filteredResults.filter { result in
                guard let version = result.minimumWatchOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: minWatchOS)
            }
        }
        if let minVisionOS {
            filteredResults = filteredResults.filter { result in
                guard let version = result.minimumVisionOS else { return false }
                return Self.isVersion(version, lessThanOrEqualTo: minVisionOS)
            }
        }

        return filteredResults
    }

    /// Force-include canonical framework and type pages (Block F)
    func forceIncludeCanonicalPages(
        results: [Search.Result],
        query: String,
        effectiveSource: String?
    ) async throws -> [Search.Result] {
        var updatedResults = results

        // Only apply for apple-docs source or when no source filter is specified
        let shouldFetchFrameworkRoot = effectiveSource == nil ||
            effectiveSource == Shared.Constants.SourcePrefix.appleDocs

        guard shouldFetchFrameworkRoot else { return results }

        // 1. Framework root page boost (#81)
        if let frameworkRoot = try await fetchFrameworkRoot(query: query) {
            updatedResults.removeAll { $0.uri == frameworkRoot.uri }
            updatedResults.insert(frameworkRoot, at: 0)
        }

        // 2. Canonical type pages for top-tier frameworks (#256)
        let canonicals = try await fetchCanonicalTypePages(query: query)
        if !canonicals.isEmpty {
            let canonicalURIs = Set(canonicals.map(\.uri))
            updatedResults.removeAll { canonicalURIs.contains($0.uri) }
            updatedResults.insert(contentsOf: canonicals, at: 0)
        }

        return updatedResults
    }

    /// Calculate final adjusted rank (Block D)
    static func computeRank(bm25Rank: Double, kindMultiplier: Double, sourceMultiplier: Double, combinedBoost: Double) -> Double {
        // CRITICAL: BM25 scores are negative, LOWER = better
        // To boost (improve rank), we need to make MORE negative
        // So we DIVIDE by multipliers (smaller multiplier = larger negative number)
        return bm25Rank / (kindMultiplier * sourceMultiplier * combinedBoost)
    }
}
