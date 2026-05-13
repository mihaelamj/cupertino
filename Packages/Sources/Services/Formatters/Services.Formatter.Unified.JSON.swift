import Foundation
import SampleIndex
import Search
import SharedConstants
import SharedCore
import SearchModels

// MARK: - Unified Search JSON Formatter

extension Services.Formatter.Unified {
    /// Formats unified search results as JSON for programmatic access
    public struct JSON: Services.Formatter.Result {
        private let query: String
        private let framework: String?

        public init(query: String, framework: String?) {
            self.query = query
            self.framework = framework
        }

        public func format(_ input: Services.Formatter.Unified.Input) -> String {
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
}

// MARK: - JSON Output Types (file-private to this formatter)

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

    init(from teaser: Services.Formatter.Unified.Input.SourceTeaserInfo) {
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

    init(from symbol: Search.MatchedSymbol) {
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

    init(from project: Sample.Index.Project) {
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
