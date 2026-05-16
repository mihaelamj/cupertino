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
            help: """
            Maximum Swift toolchain version for swift-evolution results \
            (e.g., 5.5, 6.0). Filters swift-evolution proposals to those \
            implemented at or below the given version; rows from other \
            sources are filtered out when this is set.
            """
        )
        var swift: String?

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

            // #628: validate `--framework` against the corpus before
            // running the fan-out. Per-fetcher errors are silently
            // collapsed inside `SmartQuery.answer` (so one dead source
            // can't take the rest down), which would also swallow the
            // "bogus framework" throw and make `--framework banana`
            // read as "no results" instead of a clear error.
            if let framework,
               !framework.trimmingCharacters(in: .whitespaces).isEmpty,
               let searchIndex = plan.searchIndex {
                let resolved = await (try? searchIndex.resolveFrameworkIdentifier(framework))
                    ?? framework.lowercased().replacingOccurrences(of: " ", with: "")
                let exists = await (try? searchIndex.frameworkExistsInCorpus(resolved)) ?? false
                if !exists {
                    await plan.searchIndex?.disconnect()
                    await plan.sampleService?.disconnect()
                    Cupertino.Context.composition.logging.recording.error(
                        "❌ Unknown framework: '\(framework)'. " +
                            "Run `cupertino list-frameworks` for the canonical identifier list."
                    )
                    throw ExitCode.failure
                }
            }

            let smartQuery = SearchModule.SmartQuery(fetchers: plan.fetchers)
            let rawResult = await smartQuery.answer(
                question: trimmed,
                limit: limit,
                perFetcherLimit: perSource
            )

            // #648 (CLI JSON path) — when search.db fails to OPEN
            // (vs. throws per-query), no apple-docs / hig / swift-
            // evolution / apple-archive / swift-org / swift-book
            // fetcher ran, so SmartQuery's per-fetcher classifier
            // never fired and `rawResult.degradedSources` is empty.
            // Bridge `plan.searchDBDisabledReason` (#645's classifier
            // output from the open path) into the result so CLI
            // `--format json` consumers see the same degradedSources
            // payload MCP markdown already shows post-#652.
            let result = Self.augmentWithOpenTimeDegradation(
                result: rawResult,
                disabledReason: plan.searchDBDisabledReason
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

        // MARK: - Open-time degradation injection (#648, CLI JSON path)

        /// #648 (CLI JSON path) — bridge `FetcherPlan.searchDBDisabledReason`
        /// (#645's classifier output for search.db open failures) into the
        /// `SmartResult.degradedSources` array. Mirrors
        /// `CompositeToolProvider.injectOpenTimeDegradation` on the MCP
        /// side (#648-open-time / PR #652); same 6 search.db-backed
        /// source names, same dedup-by-name merge so a future refactor
        /// that wires partial-fetcher availability won't double-count.
        /// Pure function on value types; lifted to internal scope so
        /// tests can pin the merge logic without standing up the full
        /// search command pipeline.
        static func augmentWithOpenTimeDegradation(
            result: SearchModule.SmartResult,
            disabledReason: String?
        ) -> SearchModule.SmartResult {
            guard let disabledReason else { return result }

            // The 6 sources backed by `search.db`. `samples` (samples.db)
            // and `packages` (packages.db) live in different DBs and
            // aren't affected by `search.db` being closed, so they stay
            // out of the synthesised list.
            let searchDBSources: [String] = [
                Shared.Constants.SourcePrefix.appleDocs,
                Shared.Constants.SourcePrefix.appleArchive,
                Shared.Constants.SourcePrefix.hig,
                Shared.Constants.SourcePrefix.swiftEvolution,
                Shared.Constants.SourcePrefix.swiftOrg,
                Shared.Constants.SourcePrefix.swiftBook,
            ]

            // Dedupe against entries the per-fetcher classifier may have
            // populated (currently unreachable when searchIndex is nil
            // — no fetchers run — but a future refactor wiring partial
            // availability could populate some; preserve their original
            // reason on collision because the fetcher saw it first).
            let existing = Set(result.degradedSources.map(\.name))
            let synthesised = searchDBSources
                .filter { !existing.contains($0) }
                .map { SearchModels.Search.DegradedSource(name: $0, reason: disabledReason) }

            return SearchModule.SmartResult(
                question: result.question,
                candidates: result.candidates,
                contributingSources: result.contributingSources,
                degradedSources: result.degradedSources + synthesised
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
