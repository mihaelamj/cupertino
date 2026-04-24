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
/// `PackageFTSCandidateFetcher` (#192 E6). Output format is identical to the
/// public `cupertino ask` command, so a user who learned `ask` can
/// substitute `package-search` whenever they specifically want
/// packages-only results without typing `--skip-docs`.
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

    mutating func run() async throws {
        let dbURL = db.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultPackagesDatabase

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            Logging.ConsoleLogger.error("❌ packages.db not found at \(dbURL.path)")
            Logging.ConsoleLogger.error("   Run `cupertino fetch --type package-docs` then `cupertino save --packages` first.")
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
        let fetcher = Search.PackageFTSCandidateFetcher(dbPath: dbURL)
        let smart = Search.SmartQuery(fetchers: [fetcher])
        let result = await smart.answer(question: trimmed, limit: limit, perFetcherLimit: max(20, limit))

        if result.candidates.isEmpty {
            Logging.ConsoleLogger.info("No matches for: \(trimmed)")
            return
        }

        for (i, fused) in result.candidates.enumerated() {
            let c = fused.candidate
            let owner = c.metadata["owner"] ?? ""
            let repo = c.metadata["repo"] ?? ""
            let relpath = c.metadata["relpath"] ?? c.identifier
            let module = c.metadata["module"] ?? ""
            print("══════════════════════════════════════════════════════════════════════")
            print("[\(i + 1)] \(owner)/\(repo) — \(relpath)")
            let kindLabel = c.kind ?? "?"
            if !module.isEmpty {
                print("    module: \(module)  •  kind: \(kindLabel)  •  score: \(String(format: "%.4f", fused.score))")
            } else {
                print("    kind: \(kindLabel)  •  score: \(String(format: "%.4f", fused.score))")
            }
            print("──────────────────────────────────────────────────────────────────────")
            print(c.chunk)
            print("")
        }
    }
}
