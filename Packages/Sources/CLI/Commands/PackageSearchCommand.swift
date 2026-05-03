import ArgumentParser
import Foundation
import Logging
import Search
import Shared

// MARK: - Package Search Command (hidden)

/// Hidden packages-only smart query. Invoked as:
///     cupertino package-search "how do I write a log handler in swift-log"
///
/// Thin wrapper over `Search.SmartQuery` configured with a single
/// `PackageFTSCandidateFetcher` (#192 E6). Output format is identical to
/// `cupertino search` (default fan-out mode, #239), so a user already
/// fluent with `search` can substitute `package-search` whenever they
/// specifically want packages-only results without typing `--skip-docs
/// --skip-samples`.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct PackageSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "package-search",
        abstract: "Smart query over the packages index (packages source only)",
        shouldDisplay: false
    )

    @Argument(help: "Plain-text question")
    var question: String

    @Option(name: .long, help: "Max number of chunks to return")
    var limit: Int = 3

    @Option(name: .long, help: "Override packages.db path")
    var db: String?

    @Option(
        name: .long,
        help: """
        Restrict results to packages whose declared deployment target is \
        compatible with the named platform (#220). Values: iOS, macOS, \
        tvOS, watchOS, visionOS (case-insensitive). Requires \
        --min-version. Packages with no annotation source are dropped.
        """
    )
    var platform: String?

    @Option(
        name: .long,
        help: """
        Minimum version for --platform, e.g. 16.0 / 13.0 / 10.15. \
        Lexicographic compare in SQL — works correctly for current Apple \
        platform versions (iOS 13+, macOS 11+ etc.). #220
        """
    )
    var minVersion: String?

    mutating func run() async throws {
        let dbURL = db.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultPackagesDatabase

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            Logging.ConsoleLogger.error("❌ packages.db not found at \(dbURL.path)")
            Logging.ConsoleLogger.error("   Run `cupertino fetch --type packages` then `cupertino save --packages` first.")
            throw ExitCode.failure
        }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logging.ConsoleLogger.error("❌ Question cannot be empty.")
            throw ExitCode.failure
        }

        // E6: single-fetcher SmartQuery. RRF over one input degenerates to
        // "preserve the fetcher's own ordering", so behaviour is equivalent
        // to calling `PackageQuery.answer` directly — but it goes through the
        // exact same code path as `cupertino ask`, which means future ranking
        // tweaks land in one place.
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
        let fetcher = Search.PackageFTSCandidateFetcher(
            dbPath: dbURL,
            availability: availabilityFilter
        )
        let smart = Search.SmartQuery(fetchers: [fetcher])
        let result = await smart.answer(question: trimmed, limit: limit, perFetcherLimit: max(20, limit))

        if result.candidates.isEmpty {
            Logging.ConsoleLogger.info("No matches for: \(trimmed)")
            return
        }

        for (idx, fused) in result.candidates.enumerated() {
            let cand = fused.candidate
            let owner = cand.metadata["owner"] ?? ""
            let repo = cand.metadata["repo"] ?? ""
            let relpath = cand.metadata["relpath"] ?? cand.identifier
            let module = cand.metadata["module"] ?? ""
            print("══════════════════════════════════════════════════════════════════════")
            print("[\(idx + 1)] \(owner)/\(repo) — \(relpath)")
            let kindLabel = cand.kind ?? "?"
            if !module.isEmpty {
                print("    module: \(module)  •  kind: \(kindLabel)  •  score: \(String(format: "%.4f", fused.score))")
            } else {
                print("    kind: \(kindLabel)  •  score: \(String(format: "%.4f", fused.score))")
            }
            print("──────────────────────────────────────────────────────────────────────")
            print(cand.chunk)
            print("")
        }
    }
}
