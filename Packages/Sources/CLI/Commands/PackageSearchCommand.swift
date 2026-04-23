import ArgumentParser
import Foundation
import Logging
import Search
import Shared

// MARK: - Package Search Command (hidden)

/// Hidden smart query over `~/.cupertino/packages.db`. Invoked as:
///     cupertino package-search "how do I write a log handler in swift-log"
/// Prints plain-text ranked chunks. Not advertised in `--help`; use by
/// explicitly invoking the command.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct PackageSearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "package-search",
        abstract: "Smart query over the packages index",
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

        let query = try await Search.PackageQuery(dbPath: dbURL)
        let results = try await query.answer(question, maxResults: limit)
        await query.disconnect()

        if results.isEmpty {
            Logging.ConsoleLogger.info("No matches for: \(question)")
            return
        }

        for (i, result) in results.enumerated() {
            print("══════════════════════════════════════════════════════════════════════")
            print("[\(i + 1)] \(result.owner)/\(result.repo) — \(result.relpath)")
            if let module = result.module {
                print("    module: \(module)  •  kind: \(result.kind)  •  score: \(String(format: "%.2f", result.score))")
            } else {
                print("    kind: \(result.kind)  •  score: \(String(format: "%.2f", result.score))")
            }
            print("──────────────────────────────────────────────────────────────────────")
            print(result.chunk)
            print("")
        }
    }
}
