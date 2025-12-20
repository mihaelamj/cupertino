import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Text Formatter for Unified Search

/// Formats unified search results as plain text for CLI output
public struct UnifiedSearchTextFormatter: ResultFormatter {
    private let query: String
    private let framework: String?
    private let config: SearchResultFormatConfig

    public init(query: String, framework: String?, config: SearchResultFormatConfig = .cliDefault) {
        self.query = query
        self.framework = framework
        self.config = config
    }

    public func format(_ input: UnifiedSearchInput) -> String {
        var output = "# \(query)\n\n"

        if let framework {
            output += "_Filtered to framework: \(framework)_\n\n"
        }

        let sourceCount = input.nonEmptySourceCount
        let plural = sourceCount == 1 ? "" : "s"
        output += "**Total: \(input.totalCount) results** found in \(sourceCount) source\(plural)\n\n"

        // Iterate all sources in unified order
        for (index, section) in input.allSources.enumerated() {
            let sourceNumber = index + 1
            let count = section.count
            let header = "## \(sourceNumber). \(section.info.name) (\(count)) "
            output += "\(header)\(section.info.emoji) `--source \(section.info.key)`\n\n"

            if section.isSampleSource {
                output += formatSampleResults(section.sampleResults, sourceNumber: sourceNumber)
            } else {
                output += formatDocResults(section.docResults, sourceNumber: sourceNumber)
            }
        }

        if input.totalCount == 0 {
            output += "_No results found across any source._\n\n"
        }

        // Footer: teasers for sources with more results, tips and guidance
        output += "---\n\n"

        // Show teasers for sources that hit the limit
        if let teasers = input.sourceTeasers {
            output += "**More results available:**\n"
            for teaser in teasers {
                output += "- \(teaser.displayName): use `source: \(teaser.sourcePrefix)` for more\n"
            }
            output += "\n"
        }

        // Standard tips (using shared constants for consistency with MCP)
        let sources = Shared.Constants.Search.availableSources.joined(separator: ", ")
        output += "_To narrow results, use source parameter: \(sources)_\n\n"
        output += Shared.Constants.Search.tipSemanticSearch + "\n\n"
        output += Shared.Constants.Search.tipPlatformFilters + "\n"

        return output
    }

    private func formatDocResults(_ results: [Search.Result], sourceNumber: Int) -> String {
        var output = ""
        for (index, result) in results.enumerated() {
            let resultNumber = index + 1
            output += "### \(sourceNumber).\(resultNumber) \(result.title.cleanedForDisplay)\n"
            let maxLen = Shared.Constants.Limit.summaryTruncationLength
            let summary = result.cleanedSummary.cleanedForDisplay.truncated(to: maxLen)
            if !summary.isEmpty {
                output += "\(summary)\n"
            }
            output += "- **URI:** `\(result.uri)`\n"
            if config.showAvailability,
               let availability = result.availabilityString, !availability.isEmpty {
                output += "- **Availability:** \(availability)\n"
            }
            // (#81) Show matched symbols from AST extraction
            if let symbols = result.matchedSymbols, !symbols.isEmpty {
                let symbolStr = symbols.map { "`\($0.displayString)`" }.joined(separator: ", ")
                output += "- **Symbols:** \(symbolStr)\n"
            }
            output += "\n"
        }
        return output
    }

    private func formatSampleResults(_ projects: [SampleIndex.Project], sourceNumber: Int) -> String {
        var output = ""
        for (index, project) in projects.enumerated() {
            let resultNumber = index + 1
            output += "### \(sourceNumber).\(resultNumber) \(project.title)\n"
            let maxLen = Shared.Constants.Limit.summaryTruncationLength
            let desc = project.description.cleanedForDisplay.truncated(to: maxLen)
            if !desc.isEmpty {
                output += "\(desc)\n"
            }
            output += "- **ID:** `\(project.id)`\n\n"
        }
        return output
    }
}

// MARK: - JSON Formatter for Unified Search

/// Formats unified search results as JSON for programmatic access
public struct UnifiedSearchJSONFormatter: ResultFormatter {
    private let query: String
    private let framework: String?

    public init(query: String, framework: String?) {
        self.query = query
        self.framework = framework
    }

    public func format(_ input: UnifiedSearchInput) -> String {
        // Build ordered sources array from allSources
        let sources = input.allSources.map { section -> SourceJSONOutput in
            if section.isSampleSource {
                return SourceJSONOutput(
                    info: section.info,
                    samples: section.sampleResults.map(SampleJSONOutput.init)
                )
            } else {
                return SourceJSONOutput(
                    info: section.info,
                    results: section.docResults.map(ResultJSONOutput.init)
                )
            }
        }

        let teasers = input.sourceTeasers?.map(TeaserJSONOutput.init)

        let output = JSONOutput(
            query: query,
            framework: framework,
            totalCount: input.totalCount,
            sourceCount: input.nonEmptySourceCount,
            sources: sources,
            teasers: teasers
        )

        return encodeJSON(output)
    }
}

// MARK: - JSON Output Types

private struct JSONOutput: Encodable {
    let query: String
    let framework: String?
    let totalCount: Int
    let sourceCount: Int
    let sources: [SourceJSONOutput]
    let teasers: [TeaserJSONOutput]?
}

/// Represents a single source in the ordered results
private struct SourceJSONOutput: Encodable {
    let name: String
    let key: String
    let emoji: String
    let results: [ResultJSONOutput]?
    let samples: [SampleJSONOutput]?

    init(
        info: Shared.Constants.SourcePrefix.SourceInfo,
        results: [ResultJSONOutput]? = nil,
        samples: [SampleJSONOutput]? = nil
    ) {
        name = info.name
        key = info.key
        emoji = info.emoji
        self.results = results
        self.samples = samples
    }
}

private struct TeaserJSONOutput: Encodable {
    let source: String
    let displayName: String
    let shownCount: Int
    let hasMore: Bool

    init(from teaser: UnifiedSearchInput.SourceTeaserInfo) {
        source = teaser.sourcePrefix
        displayName = teaser.displayName
        shownCount = teaser.shownCount
        hasMore = teaser.hasMore
    }
}

private struct ResultJSONOutput: Encodable {
    let title: String
    let framework: String
    let uri: String
    let availability: String?
    let summary: String
    let matchedSymbols: [SymbolJSONOutput]?

    init(from result: Search.Result) {
        title = result.title.cleanedForDisplay
        framework = result.framework
        uri = result.uri
        availability = result.availabilityString
        summary = result.cleanedSummary.cleanedForDisplay
        matchedSymbols = result.matchedSymbols?.map(SymbolJSONOutput.init)
    }
}

private struct SymbolJSONOutput: Encodable {
    let kind: String
    let name: String
    let signature: String?
    let isAsync: Bool

    init(from symbol: MatchedSymbol) {
        kind = symbol.kind
        name = symbol.name
        signature = symbol.signature
        isAsync = symbol.isAsync
    }
}

private struct SampleJSONOutput: Encodable {
    let id: String
    let title: String
    let frameworks: [String]
    let fileCount: Int
    let description: String

    init(from project: SampleIndex.Project) {
        id = project.id
        title = project.title
        frameworks = project.frameworks
        fileCount = project.fileCount
        description = project.description
    }
}

// MARK: - JSON Encoding Helper

private func encodeJSON(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(value),
          let json = String(data: data, encoding: .utf8)
    else {
        return "{\"error\": \"Failed to encode results\"}"
    }

    return json
}
