import ArgumentParser
import Foundation
import Logging
import Search
import Shared

// MARK: - Ask command (#192 section E5)

//
// Public-facing smart query: `cupertino ask "<question>"`. Fans the question
// across every configured source (packages, apple-docs, apple-archive, HIG,
// swift-evolution, swift-org, swift-book) using `Search.SmartQuery` and
// prints the fused top-N as a plain-text report.
//
// Compared to `cupertino search` (which is a thin CLI over one source):
//  - `ask` accepts free-text questions, not FTS MATCH expressions
//  - `ask` runs every source automatically, no `--source` required
//  - `ask` returns chunked excerpts (ready for LLM context), not URIs

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct AskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "Ask a natural-language question across all indexed sources"
    )

    @Argument(help: "Plain-text question, e.g. \"how do I make a SwiftUI view observable\"")
    var question: String

    @Option(name: .long, help: "Max fused results to return across all sources.")
    var limit: Int = 5

    @Option(name: .long, help: "Per-source candidate cap before rank fusion.")
    var perSource: Int = 10

    @Option(name: .long, help: "Override search.db path.")
    var searchDb: String?

    @Option(name: .long, help: "Override packages.db path.")
    var packagesDb: String?

    @Flag(name: .long, help: "Skip the packages source (useful when packages.db is absent or stale).")
    var skipPackages: Bool = false

    @Flag(name: .long, help: "Skip all apple-docs-backed sources (useful when search.db is absent).")
    var skipDocs: Bool = false

    @Option(
        name: .long,
        help: """
        Restrict packages results to those whose declared deployment \
        target is compatible with the named platform (#220). Values: \
        iOS, macOS, tvOS, watchOS, visionOS (case-insensitive). \
        Requires --min-version. Doc sources are unaffected.
        """
    )
    var platform: String?

    @Option(
        name: .long,
        help: """
        Minimum version for --platform, e.g. 16.0 / 13.0 / 10.15. \
        Lexicographic compare in SQL; works for current Apple platforms. #220
        """
    )
    var minVersion: String?

    mutating func run() async throws {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logging.ConsoleLogger.error("❌ Question cannot be empty.")
            throw ExitCode.failure
        }

        var fetchers: [any Search.CandidateFetcher] = []
        var searchIndex: Search.Index?

        // Docs-backed fetchers share one Search.Index actor.
        if !skipDocs {
            let searchDBURL = searchDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Constants.defaultSearchDatabase
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                do {
                    let index = try await Search.Index(dbPath: searchDBURL)
                    searchIndex = index
                    for source in Self.docsSources {
                        fetchers.append(Search.DocsSourceCandidateFetcher(
                            searchIndex: index,
                            source: source.prefix,
                            includeArchive: source.includeArchive
                        ))
                    }
                } catch {
                    Logging.ConsoleLogger.error("⚠️  Could not open search.db: \(error.localizedDescription)")
                }
            } else {
                Logging.ConsoleLogger.info("ℹ️  search.db not found at \(searchDBURL.path) — skipping doc sources.")
            }
        }

        // Validate the availability flags up front so the warning shown
        // before results (#220 follow-up) sees the same source of truth as
        // the packages fetcher.
        let availabilityFilter: Search.PackageQuery.AvailabilityFilter?
        switch (platform, minVersion) {
        case let (platform?, minVersion?):
            availabilityFilter = Search.PackageQuery.AvailabilityFilter(
                platform: platform,
                minVersion: minVersion
            )
        case (.some, nil), (nil, .some):
            Logging.ConsoleLogger.error(
                "❌ --platform and --min-version must be used together (#220)."
            )
            throw ExitCode.failure
        case (nil, nil):
            availabilityFilter = nil
        }

        if !skipPackages {
            let packagesDBURL = packagesDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Constants.defaultPackagesDatabase
            if FileManager.default.fileExists(atPath: packagesDBURL.path) {
                fetchers.append(Search.PackageFTSCandidateFetcher(
                    dbPath: packagesDBURL,
                    availability: availabilityFilter
                ))
            } else {
                Logging.ConsoleLogger.info("ℹ️  packages.db not found at \(packagesDBURL.path) — skipping packages.")
            }
        }

        guard !fetchers.isEmpty else {
            Logging.ConsoleLogger.error("❌ No data sources available. Run `cupertino setup` to populate them.")
            throw ExitCode.failure
        }

        let smartQuery = Search.SmartQuery(fetchers: fetchers)
        let result = await smartQuery.answer(
            question: trimmed,
            limit: limit,
            perFetcherLimit: perSource
        )

        if let index = searchIndex {
            await index.disconnect()
        }

        Self.printReport(
            result: result,
            question: trimmed,
            availabilityFilterActive: availabilityFilter != nil,
            platform: platform,
            minVersion: minVersion
        )
    }

    // MARK: - Helpers

    /// Docs-backed sources in a consistent order. `apple-archive` is included
    /// but explicitly flags `includeArchive: true` so the base search path
    /// doesn't exclude it.
    private static let docsSources: [(prefix: String, includeArchive: Bool)] = [
        (Shared.Constants.SourcePrefix.appleDocs, false),
        (Shared.Constants.SourcePrefix.appleArchive, true),
        (Shared.Constants.SourcePrefix.hig, false),
        (Shared.Constants.SourcePrefix.swiftEvolution, false),
        (Shared.Constants.SourcePrefix.swiftOrg, false),
        (Shared.Constants.SourcePrefix.swiftBook, false),
    ]

    /// Sources whose results are NOT scoped by `--platform` / `--min-version`
    /// (#220 follow-up). The packages source IS the only one that honours
    /// the filter today; everything else returns its normal ranked list.
    /// Used by `printReport` to emit a one-line notice so users can tell
    /// which results were filtered and which weren't.
    private static let unfilteredSourcesUnderPlatformFlag: [String] = [
        Shared.Constants.SourcePrefix.appleDocs,
        Shared.Constants.SourcePrefix.appleArchive,
        Shared.Constants.SourcePrefix.hig,
        Shared.Constants.SourcePrefix.swiftEvolution,
        Shared.Constants.SourcePrefix.swiftOrg,
        Shared.Constants.SourcePrefix.swiftBook,
    ]

    private static func printReport(
        result: Search.SmartResult,
        question: String,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?
    ) {
        if result.candidates.isEmpty {
            let sources = result.contributingSources.isEmpty
                ? "no sources responded"
                : "searched \(result.contributingSources.joined(separator: ", "))"
            print("No matches for: \(question)")
            print("(\(sources))")
            return
        }

        print("Question: \(question)")
        print("Searched: \(result.contributingSources.joined(separator: ", "))")

        // #220 follow-up: when --platform / --min-version is set, surface a
        // notice that doc-style sources don't honour the filter. Only print
        // when at least one of those sources actually contributed a result —
        // no need to confuse the user about a source that returned nothing.
        if availabilityFilterActive,
           let platform,
           let minVersion {
            let unfilteredContributing = result.contributingSources.filter {
                unfilteredSourcesUnderPlatformFlag.contains($0)
            }
            if !unfilteredContributing.isEmpty {
                print(
                    "ℹ️  --platform \(platform) --min-version \(minVersion) currently only "
                        + "filters the packages source. Results from "
                        + unfilteredContributing.joined(separator: ", ")
                        + " are unfiltered — apple-docs and apple-archive carry the same "
                        + "min_ios / min_macos columns in search.db, but the filter isn't "
                        + "wired through to those fetchers yet (#220 follow-up). "
                        + "swift-evolution / swift-org / swift-book use a different axis "
                        + "(Swift language version — #225)."
                )
            }
        }

        print("")

        for (idx, fused) in result.candidates.enumerated() {
            let cand = fused.candidate
            print("══════════════════════════════════════════════════════════════════════")
            print("[\(idx + 1)] \(cand.title)  •  source: \(cand.source)  •  score: \(String(format: "%.4f", fused.score))")
            print("    \(cand.identifier)")
            print("──────────────────────────────────────────────────────────────────────")
            print(cand.chunk)
            print("")
        }
    }
}
