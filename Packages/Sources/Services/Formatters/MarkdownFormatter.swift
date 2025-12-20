import Foundation
import SampleIndex
import Search
import Shared

// MARK: - Markdown Search Result Formatter

/// Formats search results as markdown for MCP tools and CLI --format markdown
public struct MarkdownSearchResultFormatter: ResultFormatter {
    private let query: String
    private let filters: SearchFilters?
    private let config: SearchResultFormatConfig
    private let teasers: TeaserResults?
    private let showPlatformTip: Bool

    public init(
        query: String,
        filters: SearchFilters? = nil,
        config: SearchResultFormatConfig = .mcpDefault,
        teasers: TeaserResults? = nil,
        showPlatformTip: Bool = true
    ) {
        self.query = query
        self.filters = filters
        self.config = config
        self.teasers = teasers
        self.showPlatformTip = showPlatformTip
    }

    public func format(_ results: [Search.Result]) -> String {
        var output = "# Search Results for \"\(query)\"\n\n"

        // Always tell the AI what source was searched
        let searchedSource = filters?.source ?? Shared.Constants.SourcePrefix.appleDocs
        output += "_Source: **\(searchedSource)**_\n\n"

        // Show other filters (not source since we just showed it)
        if let filters, filters.hasActiveFilters {
            if let framework = filters.framework {
                output += "_Filtered to framework: **\(framework)**_\n\n"
            }
            if let language = filters.language {
                output += "_Filtered to language: **\(language)**_\n\n"
            }
            if let minimumiOS = filters.minimumiOS {
                output += "_Filtered to iOS: **\(minimumiOS)+**_\n\n"
            }
            if let minimumMacOS = filters.minimumMacOS {
                output += "_Filtered to macOS: **\(minimumMacOS)+**_\n\n"
            }
            if let minimumTvOS = filters.minimumTvOS {
                output += "_Filtered to tvOS: **\(minimumTvOS)+**_\n\n"
            }
            if let minimumWatchOS = filters.minimumWatchOS {
                output += "_Filtered to watchOS: **\(minimumWatchOS)+**_\n\n"
            }
            if let minimumVisionOS = filters.minimumVisionOS {
                output += "_Filtered to visionOS: **\(minimumVisionOS)+**_\n\n"
            }
        }

        output += "Found **\(results.count)** result\(results.count == 1 ? "" : "s"):\n\n"

        if results.isEmpty {
            output += config.emptyMessage
            output += "\n\n"
            output += Shared.Constants.Search.tipSearchCapabilities
            return output
        }

        for (index, result) in results.enumerated() {
            output += "## \(index + 1). \(result.title)\n\n"
            output += "- **Framework:** `\(result.framework)`\n"
            output += "- **URI:** `\(result.uri)`\n"

            if config.showAvailability,
               let availability = result.availabilityString, !availability.isEmpty {
                output += "- **Availability:** \(availability)\n"
            }
            if config.showScore {
                output += "- **Score:** \(String(format: "%.2f", result.score))\n"
            }
            if config.showWordCount {
                output += "- **Words:** \(result.wordCount)\n"
            }
            if config.showSource {
                output += "- **Source:** \(result.source)\n"
            }
            // (#81) Show matched symbols from AST extraction
            if let symbols = result.matchedSymbols, !symbols.isEmpty {
                let symbolStr = symbols.map { "`\($0.displayString)`" }.joined(separator: ", ")
                output += "- **Symbols:** \(symbolStr)\n"
            }

            if !result.cleanedSummary.isEmpty {
                output += "\n\(result.cleanedSummary)\n\n"
            } else {
                output += "\n"
            }

            if config.showSeparators, index < results.count - 1 {
                output += "---\n\n"
            }
        }

        // Footer: teasers, tips, and guidance
        let footer = SearchFooter.singleSource(
            searchedSource,
            teasers: teasers,
            showPlatformTip: showPlatformTip
        )
        output += footer.formatMarkdown()

        return output
    }
}

// MARK: - HIG Markdown Formatter

/// Formats HIG search results as markdown
public struct HIGMarkdownFormatter: ResultFormatter {
    private let query: HIGQuery
    private let config: SearchResultFormatConfig
    private let teasers: TeaserResults?

    public init(
        query: HIGQuery,
        config: SearchResultFormatConfig = .mcpDefault,
        teasers: TeaserResults? = nil
    ) {
        self.query = query
        self.config = config
        self.teasers = teasers
    }

    public func format(_ results: [Search.Result]) -> String {
        var output = "# HIG Search Results for \"\(query.text)\"\n\n"

        // Tell the AI what source this is
        output += "_Source: **\(Shared.Constants.SourcePrefix.hig)**_\n\n"

        if let platform = query.platform {
            output += "_Platform: **\(platform)**_\n\n"
        }
        if let category = query.category {
            output += "_Category: **\(category)**_\n\n"
        }

        output += "Found **\(results.count)** guideline\(results.count == 1 ? "" : "s"):\n\n"

        if results.isEmpty {
            output += "_No Human Interface Guidelines found matching your query._\n\n"
            output += "**Tips:**\n"
            output += "- Try broader design terms (e.g., 'buttons', 'typography', 'navigation')\n"
            output += "- Specify a platform: iOS, macOS, watchOS, visionOS, tvOS\n"
            output += "- Specify a category: foundations, patterns, components, technologies, inputs\n\n"
            output += Shared.Constants.Search.tipSearchCapabilities
            return output
        }

        for (index, result) in results.enumerated() {
            output += "## \(index + 1). \(result.title)\n\n"
            output += "- **URI:** `\(result.uri)`\n"

            if config.showAvailability,
               let availability = result.availabilityString, !availability.isEmpty {
                output += "- **Availability:** \(availability)\n"
            }
            if config.showScore {
                output += "- **Score:** \(String(format: "%.2f", result.score))\n"
            }

            if !result.cleanedSummary.isEmpty {
                output += "\n\(result.cleanedSummary)\n\n"
            } else {
                output += "\n"
            }

            if config.showSeparators, index < results.count - 1 {
                output += "---\n\n"
            }
        }

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(
            Shared.Constants.SourcePrefix.hig,
            teasers: teasers
        )
        output += footer.formatMarkdown()

        return output
    }
}

// MARK: - Frameworks Markdown Formatter

/// Formats framework list as markdown
public struct FrameworksMarkdownFormatter: ResultFormatter {
    private let totalDocs: Int

    public init(totalDocs: Int) {
        self.totalDocs = totalDocs
    }

    public func format(_ frameworks: [String: Int]) -> String {
        var output = "# Available Frameworks\n\n"
        output += "Total documents: **\(totalDocs)**\n\n"

        if frameworks.isEmpty {
            let cmd = "\(Shared.Constants.App.commandName) \(Shared.Constants.Command.buildIndex)"
            output += Shared.Constants.Search.messageNoFrameworks(buildIndexCommand: cmd)
            return output
        }

        output += "| Framework | Documents |\n"
        output += "|-----------|----------:|\n"

        // Sort by document count (descending)
        for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
            output += "| `\(framework)` | \(count) |\n"
        }

        // Footer: tips and guidance
        let footer = SearchFooter.singleSource(Shared.Constants.SourcePrefix.appleDocs)
        output += footer.formatMarkdown()

        return output
    }
}

// MARK: - Unified Search Markdown Formatter

/// Input data for unified search formatting - includes ALL sources
public struct UnifiedSearchInput: Sendable {
    public let docResults: [Search.Result]
    public let archiveResults: [Search.Result]
    public let sampleResults: [SampleIndex.Project]
    public let higResults: [Search.Result]
    public let swiftEvolutionResults: [Search.Result]
    public let swiftOrgResults: [Search.Result]
    public let swiftBookResults: [Search.Result]
    public let packagesResults: [Search.Result]
    public let limit: Int // The limit used per source, for teaser calculation

    public init(
        docResults: [Search.Result] = [],
        archiveResults: [Search.Result] = [],
        sampleResults: [SampleIndex.Project] = [],
        higResults: [Search.Result] = [],
        swiftEvolutionResults: [Search.Result] = [],
        swiftOrgResults: [Search.Result] = [],
        swiftBookResults: [Search.Result] = [],
        packagesResults: [Search.Result] = [],
        limit: Int = 10
    ) {
        self.docResults = docResults
        self.archiveResults = archiveResults
        self.sampleResults = sampleResults
        self.higResults = higResults
        self.swiftEvolutionResults = swiftEvolutionResults
        self.swiftOrgResults = swiftOrgResults
        self.swiftBookResults = swiftBookResults
        self.packagesResults = packagesResults
        self.limit = limit
    }

    /// Total number of results across all sources
    public var totalCount: Int {
        docResults.count + archiveResults.count + sampleResults.count +
            higResults.count + swiftEvolutionResults.count + swiftOrgResults.count +
            swiftBookResults.count + packagesResults.count
    }

    /// Number of sources that returned results
    public var nonEmptySourceCount: Int {
        allSources.count
    }

    /// Represents a source section for iteration
    public struct SourceSection: Sendable {
        public let info: Shared.Constants.SourcePrefix.SourceInfo
        public let docResults: [Search.Result]
        public let sampleResults: [SampleIndex.Project]

        public var isEmpty: Bool { docResults.isEmpty && sampleResults.isEmpty }
        public var count: Int { docResults.count + sampleResults.count }
        public var isSampleSource: Bool { !sampleResults.isEmpty }

        /// Create from doc results if not empty, nil otherwise
        public static func fromDocs(
            _ info: Shared.Constants.SourcePrefix.SourceInfo,
            _ results: [Search.Result]
        ) -> SourceSection? {
            guard !results.isEmpty else { return nil }
            return SourceSection(info: info, docResults: results, sampleResults: [])
        }

        /// Create from sample results if not empty, nil otherwise
        public static func fromSamples(
            _ info: Shared.Constants.SourcePrefix.SourceInfo,
            _ results: [SampleIndex.Project]
        ) -> SourceSection? {
            guard !results.isEmpty else { return nil }
            return SourceSection(info: info, docResults: [], sampleResults: results)
        }
    }

    /// Returns all non-empty sources in display order
    public var allSources: [SourceSection] {
        typealias Info = Shared.Constants.SourcePrefix
        typealias Section = SourceSection

        // Order: Apple Docs, Archive, Samples, HIG, Swift Evolution, Swift.org, Swift Book, Packages
        return [
            Section.fromDocs(Info.infoAppleDocs, docResults),
            Section.fromDocs(Info.infoArchive, archiveResults),
            Section.fromSamples(Info.infoSamples, sampleResults),
            Section.fromDocs(Info.infoHIG, higResults),
            Section.fromDocs(Info.infoSwiftEvolution, swiftEvolutionResults),
            Section.fromDocs(Info.infoSwiftOrg, swiftOrgResults),
            Section.fromDocs(Info.infoSwiftBook, swiftBookResults),
            Section.fromDocs(Info.infoPackages, packagesResults),
        ].compactMap { $0 }
    }

    /// Teaser info for sources that hit the limit (likely have more results)
    public struct SourceTeaserInfo: Sendable {
        public let info: Shared.Constants.SourcePrefix.SourceInfo
        public let shownCount: Int
        public let hasMore: Bool // True if count == limit (likely more available)

        // Convenience accessors
        public var displayName: String { info.name }
        public var sourcePrefix: String { info.key }
        public var emoji: String { info.emoji }
    }

    /// Returns teaser info for all sources that hit the limit (nil if none)
    public var sourceTeasers: [SourceTeaserInfo]? {
        typealias Info = Shared.Constants.SourcePrefix

        // Check each source in display order
        let sourcesWithCounts: [(info: Info.SourceInfo, count: Int)] = [
            (Info.infoAppleDocs, docResults.count),
            (Info.infoArchive, archiveResults.count),
            (Info.infoSamples, sampleResults.count),
            (Info.infoHIG, higResults.count),
            (Info.infoSwiftEvolution, swiftEvolutionResults.count),
            (Info.infoSwiftOrg, swiftOrgResults.count),
            (Info.infoSwiftBook, swiftBookResults.count),
            (Info.infoPackages, packagesResults.count),
        ]

        let teasers = sourcesWithCounts.compactMap { info, count -> SourceTeaserInfo? in
            guard count == limit else { return nil }
            return SourceTeaserInfo(info: info, shownCount: count, hasMore: true)
        }

        return teasers.isEmpty ? nil : teasers
    }
}

/// Formats unified search results (ALL sources) as markdown
public struct UnifiedSearchMarkdownFormatter: ResultFormatter {
    private let query: String
    private let framework: String?
    private let config: SearchResultFormatConfig

    public init(
        query: String,
        framework: String? = nil,
        config: SearchResultFormatConfig = .mcpDefault
    ) {
        self.query = query
        self.framework = framework
        self.config = config
    }

    public func format(_ input: UnifiedSearchInput) -> String {
        var output = "# Unified Search: \"\(query)\"\n\n"

        if let framework {
            output += "_Filtered to framework: **\(framework)**_\n\n"
        }

        // Tell the AI exactly what sources were searched
        let allSources = Shared.Constants.Search.availableSources.joined(separator: ", ")
        output += "_Searched ALL sources: \(allSources)_\n\n"

        let sourceCount = input.nonEmptySourceCount
        let plural = sourceCount == 1 ? "" : "s"
        output += "**Total: \(input.totalCount) results** found in \(sourceCount) source\(plural)\n\n"

        // Iterate all sources in unified order
        for section in input.allSources {
            output += "## \(section.info.emoji) \(section.info.name) (\(section.count))\n\n"
            if section.isSampleSource {
                output += formatSampleResults(section.sampleResults)
            } else {
                output += formatDocResults(section.docResults)
            }
        }

        // Show message if no results at all
        if input.totalCount == 0 {
            output += "_No results found across any source._\n\n"
        }

        // Footer: teasers for sources with more results, tips and guidance
        output += "\n---\n\n"

        // Show teasers for sources that hit the limit
        if let teasers = input.sourceTeasers {
            output += "**More results available:**\n"
            for teaser in teasers {
                output += "- \(teaser.emoji) \(teaser.displayName): _use `source: \(teaser.sourcePrefix)` for more_\n"
            }
            output += "\n"
        }

        // Standard tips
        let sources = Shared.Constants.Search.availableSources.joined(separator: ", ")
        output += "_To narrow results, use `source` parameter: \(sources)_\n\n"
        output += Shared.Constants.Search.tipSemanticSearch + "\n\n"
        output += Shared.Constants.Search.tipPlatformFilters + "\n"

        return output
    }

    private func formatDocResults(_ results: [Search.Result]) -> String {
        var output = ""
        let maxLen = Shared.Constants.Limit.summaryTruncationLength
        for result in results {
            output += "- **\(result.title.cleanedForDisplay)**\n"
            let summary = result.cleanedSummary.cleanedForDisplay.truncated(to: maxLen)
            if !summary.isEmpty {
                output += "  - \(summary)\n"
            }
            output += "  - URI: `\(result.uri)`\n"
            if config.showAvailability,
               let availability = result.availabilityString, !availability.isEmpty {
                output += "  - Availability: \(availability)\n"
            }
            // (#81) Show matched symbols from AST extraction
            if let symbols = result.matchedSymbols, !symbols.isEmpty {
                let symbolStr = symbols.map { "`\($0.displayString)`" }.joined(separator: ", ")
                output += "  - Symbols: \(symbolStr)\n"
            }
        }
        output += "\n"
        return output
    }

    private func formatSampleResults(_ projects: [SampleIndex.Project]) -> String {
        var output = ""
        let maxLen = Shared.Constants.Limit.summaryTruncationLength
        for project in projects {
            output += "- **\(project.title)**\n"
            let desc = project.description.cleanedForDisplay.truncated(to: maxLen)
            if !desc.isEmpty {
                output += "  - \(desc)\n"
            }
            output += "  - ID: `\(project.id)`\n"
            output += "  - Frameworks: \(project.frameworks.joined(separator: ", "))\n"
        }
        output += "\n"
        return output
    }
}
