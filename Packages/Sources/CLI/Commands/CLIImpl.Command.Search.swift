import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SampleIndex
import Search
import SearchModels
import Services
import ServicesModels
import SharedConstants
// MARK: - Search Command

/// CLI command for unified search across all documentation sources.
/// Mirrors MCP `search` tool functionality with `--source` parameter routing.
///
/// After #239 the default (no `--source`) path runs `SearchModule.SmartQuery` —
/// a fan-out across every available DB with reciprocal-rank-fusion ranking
/// and chunked output, replacing what `cupertino ask` used to do. The
/// single-source `--source <name>` path still runs the source-specific
/// list-style formatters.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search",
            abstract: "Search Apple documentation, samples, HIG, and more",
            discussion: """
            Unified search across all documentation sources. By default, searches ALL sources
            in parallel and returns chunked excerpts ranked by reciprocal-rank fusion
            (absorbed from the removed `cupertino ask`). Use --source to narrow to one source
            and get the source-specific list view instead.

            SOURCES:
              (default)       Fan out across every available DB (chunked, RRF-fused)
              apple-docs      Modern Apple API documentation only
              samples         Sample code projects with working examples
              hig             Human Interface Guidelines
              apple-archive   Legacy guides (Core Animation, Quartz 2D, KVO/KVC)
              swift-evolution Swift Evolution proposals
              swift-org       Swift.org documentation
              swift-book      The Swift Programming Language book
              packages        Swift package documentation

            SEMANTIC SEARCH:
              Search includes AST-extracted symbols from Swift source code.
              Find @Observable classes, async functions, View conformances, etc.
              Works across both documentation and sample code.

            EXAMPLES:
              cupertino search "how do I make a SwiftUI view observable"
              cupertino search "@Observable" --source samples
              cupertino search "Core Animation" --source apple-archive
              cupertino search "button styles" --source samples
              cupertino search "async throws" --source apple-docs
              cupertino search "actor reentrancy" --skip-docs
            """
        )

        @Argument(help: "Search query")
        var query: String

        @Option(
            name: .shortAndLong,
            help: """
            Filter by source: apple-docs, samples, hig, apple-archive, swift-evolution, swift-org, swift-book, packages, all
            """
        )
        var source: String?

        @Flag(
            name: .long,
            help: "Include Apple Archive documentation in results (excluded by default)"
        )
        var includeArchive: Bool = false

        @Option(
            name: .shortAndLong,
            help: "Filter by framework (e.g., swiftui, foundation, uikit)"
        )
        var framework: String?

        @Option(
            name: .shortAndLong,
            help: "Filter by programming language: swift, objc"
        )
        var language: String?

        @Option(
            name: .long,
            help: "Maximum number of results to return"
        )
        var limit: Int = Shared.Constants.Limit.defaultSearchLimit

        @Option(
            name: .long,
            help: "Filter to APIs available on iOS version (e.g., 13.0, 15.0)"
        )
        var minIos: String?

        @Option(
            name: .long,
            help: "Filter to APIs available on macOS version (e.g., 10.15, 12.0)"
        )
        var minMacos: String?

        @Option(
            name: .long,
            help: "Filter to APIs available on tvOS version (e.g., 13.0, 15.0)"
        )
        var minTvos: String?

        @Option(
            name: .long,
            help: "Filter to APIs available on watchOS version (e.g., 6.0, 8.0)"
        )
        var minWatchos: String?

        @Option(
            name: .long,
            help: "Filter to APIs available on visionOS version (e.g., 1.0, 2.0)"
        )
        var minVisionos: String?

        @Option(
            name: .long,
            help: "Path to search database (search.db)"
        )
        var searchDb: String?

        @Option(
            name: .long,
            help: "Path to packages database (packages.db). Used in fan-out mode and `--source packages`."
        )
        var packagesDb: String?

        @Option(
            name: .long,
            help: "Path to sample index database (samples.db)"
        )
        var sampleDb: String?

        @Option(
            name: .long,
            help: "Per-source candidate cap before reciprocal-rank fusion. Only applies in fan-out mode (no --source). Default 10."
        )
        var perSource: Int = 10

        @Flag(
            name: .long,
            help: "Skip every apple-docs-backed source. Fan-out mode only."
        )
        var skipDocs: Bool = false

        @Flag(
            name: .long,
            help: "Skip the packages source. Fan-out mode only."
        )
        var skipPackages: Bool = false

        @Flag(
            name: .long,
            help: "Skip the samples source. Fan-out mode only."
        )
        var skipSamples: Bool = false

        @Flag(
            name: .long,
            help: """
            Trim each result's excerpt to its first few lines for quick triage. \
            Read-full link, tips, and see-also still print. Fan-out mode + \
            text/markdown only — JSON keeps full chunks for programmatic consumers.
            """
        )
        var brief: Bool = false

        @Option(
            name: .long,
            help: """
            Restrict packages + samples + apple-docs results to the named platform's \
            deployment target. Values: iOS, macOS, tvOS, watchOS, visionOS \
            (case-insensitive). Requires --min-version. Fan-out mode only.
            """
        )
        var platform: String?

        @Option(
            name: .long,
            help: "Minimum version for --platform, e.g. 16.0 / 13.0 / 10.15. Lexicographic compare in SQL."
        )
        var minVersion: String?

        @Option(
            name: .long,
            help: "Output format: text (default), json, markdown"
        )
        var format: OutputFormat = .text

        mutating func run() async throws {
            switch source {
            case Shared.Constants.SourcePrefix.samples, Shared.Constants.SourcePrefix.appleSampleCode:
                try await runSampleSearch()
            case Shared.Constants.SourcePrefix.hig:
                try await runHIGSearch()
            case Shared.Constants.SourcePrefix.packages:
                // packages live in their own DB (packages.db), not search.db.
                // The docs runner queries search.db only and would silently
                // return [] here. Use the dedicated single-fetcher SmartQuery
                // path instead so packages.db is actually consulted (#261).
                try await runPackageSearch()
            case Shared.Constants.SourcePrefix.appleDocs,
                 Shared.Constants.SourcePrefix.appleArchive,
                 Shared.Constants.SourcePrefix.swiftEvolution,
                 Shared.Constants.SourcePrefix.swiftOrg,
                 Shared.Constants.SourcePrefix.swiftBook:
                try await runDocsSearch()
            default:
                // Default (nil or "all") triggers the SmartQuery fan-out.
                try await runUnifiedSearch()
            }
        }

        // MARK: - Per-source runners moved to CLIImpl.Command.Search+SourceRunners.swift

        // MARK: - Unified Search (All Sources, fan-out + RRF) (#239)

        /// Replaces the previous `Services.UnifiedSearchService` path with the SmartQuery
        /// fan-out absorbed from `cupertino ask`. Default behaviour when no
        /// `--source` is passed.
        private func runUnifiedSearch() async throws {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Cupertino.Context.composition.logging.recording.error("❌ Query cannot be empty.")
                throw ExitCode.failure
            }

            let availabilityFilter = try resolveAvailabilityFilter()
            let plan = await buildFetchers(availabilityFilter: availabilityFilter)
            guard !plan.fetchers.isEmpty else {
                Cupertino.Context.composition.logging.recording.error(
                    "❌ No data sources available. Run `cupertino setup` to populate them."
                )
                throw ExitCode.failure
            }

            let smartQuery = SearchModule.SmartQuery(fetchers: plan.fetchers)
            let result = await smartQuery.answer(
                question: trimmed,
                limit: limit,
                perFetcherLimit: perSource
            )

            if let index = plan.searchIndex {
                await index.disconnect()
            }
            if let service = plan.sampleService {
                await service.disconnect()
            }

            Self.printSmartReport(
                result: result,
                question: trimmed,
                availabilityFilterActive: availabilityFilter != nil,
                platform: platform,
                minVersion: minVersion,
                format: format,
                brief: brief
            )
        }

        // MARK: - Path Resolution

        func resolveSampleDbPath() -> URL {
            if let sampleDb {
                return URL(fileURLWithPath: sampleDb).expandingTildeInPath
            }
            // Path-DI composition sub-root (#535).
            return Sample.Index.databasePath(baseDirectory: Shared.Paths.live().baseDirectory)
        }
    }
}

// MARK: - Output Format

extension CLIImpl.Command.Search {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }
}
