import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SampleIndex
import SearchAPI
import SearchModels
import Services
import ServicesModels
import SharedConstants

// MARK: - Search Command

/// CLI command for unified search across all documentation sources.
/// Mirrors MCP `search` tool functionality with `--source` parameter routing.
///
/// After #239 the default (no `--source`) path runs `SearchModule.SmartQuery` --
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
            in parallel and returns chunked excerpts ranked by reciprocal-rank fusion. Use
            --source to narrow to one source and get the source-specific list view instead.

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
            help: """
            Restrict packages results to packages that import the given \
            Apple framework module (e.g., SwiftUI, Combine). Filters by \
            package_metadata.apple_imports_json, populated by the #837 \
            postprocessor. No-op on non-packages sources.
            """
        )
        var appleImports: String?

        @Option(
            name: .long,
            help: """
            Override the path used for every docs source's database. Legacy debug \
            knob: post-#1037 each docs source resolves to its own per-source DB \
            (apple-documentation.db / hig.db / apple-archive.db / swift-evolution.db / \
            swift-org.db / swift-book.db); passing this opens the single file for \
            every source-prefix the fan-out queries. Mostly useful for tests + the \
            migration window from a legacy monolithic search.db.
            """
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
            text/markdown only -- JSON keeps full chunks for programmatic consumers.
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
            // 2026-05-26 audit Finding 14.2: dispatch via
            // `Search.SourceProvider.searchRoute` instead of enumerating
            // source-id literals. Pre-fix the switch hardcoded 8 source
            // ids; adding a new source required editing this file.
            // Post-fix the route is the source's own declared property,
            // so a NEW source plugs in by setting `searchRoute = .docs`
            // (or `.hig` / `.samples` / `.packages` for bespoke
            // routing) and the dispatch finds it via `registry.entry(for:)`.
            //
            // Legacy `apple-sample-code` is accepted as an alias for
            // `samples` because both ids flow into the same SampleCodeSource.
            // Empty `source` (nil / "" / "all") falls through to the
            // unified SmartQuery fan-out.
            let registry = CLIImpl.makeProductionSourceRegistry()
            let route: SearchModels.Search.SearchRoute
            if let source, !source.isEmpty {
                let canonicalID = source == Shared.Constants.SourcePrefix.appleSampleCode
                    ? Shared.Constants.SourcePrefix.samples
                    : source
                route = registry.entry(for: canonicalID)?.provider.searchRoute ?? .unified
            } else {
                route = .unified
            }
            switch route {
            case .samples:
                try await runSampleSearch()
            case .hig:
                try await runHIGSearch()
            case .packages:
                // packages live in their own DB (packages.db), not search.db.
                // The docs runner queries search.db only and would silently
                // return [] here. Use the dedicated single-fetcher SmartQuery
                // path instead so packages.db is actually consulted (#261).
                try await runPackageSearch()
            case .docs:
                try await runDocsSearch()
            case .unified:
                // Default (nil source / "all" / future registered sources
                // whose searchRoute is .unified) triggers SmartQuery fan-out.
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
            // Post-#1037 framework partitioning lives in
            // `apple-documentation.db`; resolve through that source-id.
            if let framework,
               !framework.trimmingCharacters(in: .whitespaces).isEmpty,
               let appleDocsIndex = plan.docsIndexes[Self.frameworkValidationSourceID] {
                let resolved = await (try? appleDocsIndex.resolveFrameworkIdentifier(framework))
                    ?? framework.lowercased().replacingOccurrences(of: " ", with: "")
                let exists = await (try? appleDocsIndex.frameworkExistsInCorpus(resolved)) ?? false
                if !exists {
                    for index in plan.docsIndexes.values {
                        await index.disconnect()
                    }
                    await plan.sampleService?.disconnect()
                    Cupertino.Context.composition.logging.recording.error(
                        "❌ Unknown framework: '\(framework)'. " +
                            "Run `cupertino list-frameworks` for the canonical identifier list."
                    )
                    throw ExitCode.failure
                }
            }

            // #1045 Gap 1 wiring: derive RRF fusion weights from each
            // registered provider's `properties.rankWeight`. Production
            // call site uses `CLIImpl.makeSmartQuerySourceWeights(...)`
            // so the assembly logic is single-sourced + behavioural
            // tests can exercise it directly.
            let smartQueryWeights = CLIImpl.makeSmartQuerySourceWeights(
                registry: CLIImpl.makeProductionSourceRegistry()
            )
            let smartQuery = SearchModule.SmartQuery(
                fetchers: plan.fetchers,
                sourceWeightsOverride: smartQueryWeights
            )
            let rawResult = await smartQuery.answer(
                question: trimmed,
                limit: limit,
                perFetcherLimit: perSource
            )

            // #648 (CLI JSON path) -- when a per-source DB fails to OPEN
            // (vs. throws per-query), that source's fetcher never ran,
            // so SmartQuery's per-fetcher classifier never fired for
            // it and `rawResult.degradedSources` is empty for that
            // source. Bridge `plan.disabledReasonsBySource` (#645's
            // classifier output from the open path, lifted to a
            // per-source dictionary post-#1037) into the result so
            // CLI `--format json` consumers see the same
            // `degradedSources` payload MCP markdown already shows
            // post-#652.
            let result = Self.augmentWithOpenTimeDegradation(
                result: rawResult,
                disabledReasonsBySource: plan.disabledReasonsBySource
            )

            for index in plan.docsIndexes.values {
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

        /// #648 (CLI JSON path) -- bridge `FetcherPlan.disabledReasonsBySource`
        /// (#645's classifier output for per-source DB open failures) into
        /// the `SmartResult.degradedSources` array. Mirrors
        /// `CompositeToolProvider.injectOpenTimeDegradation` on the MCP
        /// side (#648-open-time / PR #652).
        ///
        /// Post-#1037 the input is a `[sourceID: reason]` dictionary
        /// (one entry per per-source DB that exists but couldn't open),
        /// replacing the legacy single-string `disabledReason` that
        /// blanketed every search.db-backed source uniformly. A partial
        /// failure (e.g. `hig.db` stale while the rest opened cleanly)
        /// now surfaces just `hig` as degraded rather than fabricating
        /// six fake `DegradedSource` entries.
        ///
        /// Dedup against entries the per-fetcher classifier may have
        /// populated (preserve their original reason on collision --
        /// the fetcher saw the error first). Pure function on value
        /// types; lifted to internal scope so tests can pin the merge
        /// logic without standing up the full search command pipeline.
        static func augmentWithOpenTimeDegradation(
            result: SearchModule.SmartResult,
            disabledReasonsBySource: [String: String]
        ) -> SearchModule.SmartResult {
            guard !disabledReasonsBySource.isEmpty else { return result }

            let existing = Set(result.degradedSources.map(\.name))
            // Sort by source-id for deterministic output (CLI JSON
            // consumers + tests depend on a stable ordering; a
            // dictionary's iteration order is unstable).
            let synthesised = disabledReasonsBySource
                .filter { !existing.contains($0.key) }
                .sorted(by: { $0.key < $1.key })
                .map { SearchModels.Search.DegradedSource(name: $0.key, reason: $0.value) }

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
