import ArgumentParser
import Core
import Foundation
import Logging
import LoggingModels
#if canImport(AppKit)
import AppKit
#endif
#if canImport(WebKit)
import CoreJSONParser
import CoreProtocols
import WebKit
#endif

// MARK: - Resolve-Refs Command

extension CLIImpl.Command {
    struct ResolveRefs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resolve-refs",
            abstract: "Rewrite unresolved doc:// markers in saved page rawMarkdown",
            discussion: """
            Walks a directory of saved StructuredDocumentationPage JSON files
            (typically from a `--discovery-mode json-only` crawl), harvests a
            global identifier→title map from each page's sections[].items[],
            and rewrites every `doc://com.apple.<bundle>/...` marker in
            rawMarkdown to the readable title.

            This is a pure post-process pass: no network calls, no recrawl.
            Markers pointing to pages no other page references will be left
            intact and reported in the unresolved-markers report.

            See https://github.com/mihaelamj/cupertino/issues/208
            """
        )

        @Option(
            name: .long,
            help: "Directory of saved page JSONs (e.g. ~/.cupertino/_docs)"
        )
        var input: String

        @Flag(
            name: .long,
            help: "After harvest+rewrite, fetch titles for the still-unresolved markers via Apple's JSON API."
        )
        var useNetwork: Bool = false

        @Flag(
            name: .long,
            help: "When --use-network is set, also fall back to WKWebView for markers that the JSON API can't serve. Slow; macOS only."
        )
        var useWebview: Bool = false

        @Flag(
            name: .long,
            help: "Print unresolved doc:// markers (sorted, deduped) to stdout."
        )
        var printUnresolved: Bool = false

        mutating func run() async throws {
            let dir = URL(fileURLWithPath: input).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: dir.path) else {
                Cupertino.Context.composition.logging.recording.error("Directory does not exist: \(dir.path)")
                throw ExitCode.failure
            }

            Cupertino.Context.composition.logging.recording.info("Resolving doc:// markers in \(dir.path)")
            let resolver = Core.JSONParser.RefResolver(inputDirectory: dir)

            let fetcher = try await makeFetcher()
            let (stats, unresolved): (Core.JSONParser.RefResolver.Stats, Set<String>)
            if let fetcher {
                (stats, unresolved) = try await resolver.runWithFetcher(fetcher) { done, total in
                    if done % 50 == 0 || done == total {
                        Cupertino.Context.composition.logging.recording.info("  network resolve: \(done)/\(total)")
                    }
                }
            } else {
                (stats, unresolved) = try resolver.run()
            }

            Cupertino.Context.composition.logging.recording.info("Pages scanned:                  \(stats.pagesScanned)")
            Cupertino.Context.composition.logging.recording.info("Refs harvested:                 \(stats.refsHarvested)")
            Cupertino.Context.composition.logging.recording.info("Pages rewritten:                \(stats.pagesRewritten)")
            Cupertino.Context.composition.logging.recording.info("doc:// markers found:           \(stats.markersFound)")
            Cupertino.Context.composition.logging.recording.info("Resolved from harvest:          \(stats.markersResolvedFromHarvest)")
            Cupertino.Context.composition.logging.recording.info("Resolved from network:          \(stats.markersResolvedFromNetwork)")
            Cupertino.Context.composition.logging.recording.info("Unresolved (unique):            \(unresolved.count)")

            // Persist a report next to the corpus.
            let report = ResolveReport(
                generatedAt: Date(),
                inputDirectory: dir.path,
                stats: stats,
                unresolvedMarkers: unresolved.sorted()
            )
            let reportURL = dir.appendingPathComponent("resolve-refs-report.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: reportURL)
            Cupertino.Context.composition.logging.recording.info("Report: \(reportURL.path)")

            if printUnresolved {
                for marker in report.unresolvedMarkers {
                    print(marker)
                }
            }
        }

        private struct ResolveReport: Codable {
            let generatedAt: Date
            let inputDirectory: String
            let stats: Core.JSONParser.RefResolver.Stats
            let unresolvedMarkers: [String]
        }

        /// Build the title-fetcher chain based on `--use-network` /
        /// `--use-webview` flags. Returns nil when no network resolution
        /// should happen (default behaviour).
        private func makeFetcher() async throws -> (any Core.JSONParser.RefResolver.TitleFetcher)? {
            guard useNetwork else {
                if useWebview {
                    Cupertino.Context.composition.logging.recording.error("--use-webview requires --use-network")
                    throw ExitCode.failure
                }
                return nil
            }

            let json = Core.JSONParser.AppleJSONAPITitleFetcher()
            guard useWebview else {
                return json
            }

            #if canImport(AppKit) && canImport(WebKit)
            // WKWebView needs the AppKit runloop attached (otherwise its
            // navigation observer never fires). The same bootstrap the auth
            // flow in SampleCodeDownloader uses, but headless — we don't
            // surface a Dock icon for a background resolve pass.
            let webView = await MainActor.run { () -> any Core.JSONParser.RefResolver.TitleFetcher in
                NSApplication.shared.setActivationPolicy(.prohibited)
                NSApplication.shared.finishLaunching()
                return Core.JSONParser.WKWebViewTitleFetcher()
            }
            return Core.JSONParser.CompositeTitleFetcher(primary: json, fallback: webView)
            #else
            Cupertino.Context.composition.logging.recording.error("--use-webview is only supported on macOS")
            throw ExitCode.failure
            #endif
        }
    }
}
