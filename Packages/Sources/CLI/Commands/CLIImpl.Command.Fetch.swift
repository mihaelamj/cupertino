import ArgumentParser
import Availability
import AvailabilityFoundationNetworking
import AvailabilityModels
import Core
import CorePackageIndexing
import CorePackageIndexingModels
import CoreProtocols
import CoreSampleCode
import CoreSampleCodeModels
import CoreSampleCodeWebKit
import Crawler
import CrawlerModels
import CrawlerWebKit
import Foundation
import Ingest
import Logging
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants

/// Lets ArgumentParser parse `--discovery-mode <mode>` directly into the
/// shared enum. The conformance lives here (not in Shared) so the Shared
/// module doesn't take on an ArgumentParser dependency.
extension Shared.Configuration.DiscoveryMode: ExpressibleByArgument {}

// MARK: - Fetch Command

// #673 Phase D iter-5: file_length stays as the only remaining
// file-level blanket — the rule has no per-declaration form, and
// the fetch command's option surface (10+ types, 30+ flags) puts
// this file past 1000 lines on its own. Per-type and per-function
// disables for the rest are scoped below.
// swiftlint:disable file_length

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    /// #673 Phase D iter-5: 916-line struct — ArgumentParser doesn't
    /// support partial-struct command composition, so every `@Option`
    /// / `@Flag` for every `--type` value must live on one struct.
    // swiftlint:disable:next type_body_length
    struct Fetch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fetch",
            abstract: "Download documentation, packages, and sample code for local indexing",
            discussion: """
            Downloads content from Apple and GitHub into ~/.cupertino/ ready for 'cupertino save'.

            SOURCES (--source). Post-#1031 each source is the canonical ID from the per-source target registry.

              apple-docs        Apple developer documentation (default)
              swift-org         Swift.org documentation
              swift-evolution   Swift Evolution proposals
              hig               Human Interface Guidelines
              apple-archive     Apple Archive guides (legacy Core Animation, Quartz 2D, KVO/KVC, etc.)
              availability      Update API availability metadata for an existing docs corpus (on-disk maintenance pass; not a registry source)
              packages          Swift package metadata + source archives, two-stage fetch:
                                  Stage 1: refresh metadata from Swift Package Index
                                  Stage 2: download GitHub source archives
                                Use --skip-metadata or --skip-archives to run only one stage.
                                Use --annotate-availability after stage 2 to write availability.json.
              apple-sample-code Sample code zip archives from Apple (legacy bundle download; prefer 'samples')
              samples           Apple sample-code projects from GitHub (recommended)
              all               Run all sources in parallel

            EXAMPLES
              cupertino fetch                                  # Apple docs (default)
              cupertino fetch --source swift-evolution         # Swift Evolution proposals
              cupertino fetch --source packages                # package metadata + archives
              cupertino fetch --source packages --skip-metadata    # archives only
              cupertino fetch --source packages --skip-archives    # metadata only
              cupertino fetch --source samples                 # Apple sample-code from GitHub
            """
        )

        @Option(
            name: .long,
            help: """
            Source to fetch (canonical id from the registry post-#1007 source-unification): \
            apple-docs (Apple), swift-org (Swift.org), swift-evolution (Swift Evolution), \
            packages (Swift package metadata + archives, see --skip-metadata / --skip-archives), \
            apple-sample-code (sample code zip from Apple), samples (sample code from GitHub, recommended), \
            apple-archive (Apple Archive guides), hig (Human Interface Guidelines), \
            availability (API version info for existing docs, maintenance pass), \
            all (all sources in parallel)
            """
        )
        var source: String = Shared.Constants.SourcePrefix.appleDocs

        @Option(name: .long, help: "Start URL to crawl from (overrides --type default)")
        var startURL: String?

        @Option(name: .long, help: "Maximum number of pages to crawl")
        var maxPages: Int = Shared.Constants.Limit.defaultMaxPages

        @Option(name: .long, help: "Maximum depth to crawl")
        var maxDepth: Int = 15

        @Option(name: .long, help: "Output directory for documentation")
        var outputDir: String?

        @Option(
            name: .long,
            help: """
            Allowed URL prefixes (comma-separated). \
            If not specified, auto-detects based on start URL
            """
        )
        var allowedPrefixes: String?

        @Flag(name: .long, help: "Force recrawl of all pages (re-fetch even unchanged content)")
        var force: Bool = false

        @Flag(name: .long, help: "Ignore any saved session and start fresh from the seed URL")
        var startClean: Bool = false

        @Flag(
            name: .long,
            help: """
            Re-queue URLs that errored before save (visited but missing from \
            the pages dict). Use after a filename or save bug is fixed to \
            retry the affected pages without re-crawling the whole corpus.
            """
        )
        var retryErrors: Bool = false

        @Option(
            name: .long,
            help: """
            Path to a known-good baseline corpus directory (e.g. a prior \
            cupertino-docs/docs snapshot). On startup, URLs present in the \
            baseline but not in the current crawl's known set (queue / visited \
            / pages) are prepended to the queue so the resumed crawl recovers \
            gaps without re-crawling the whole corpus. Comparison is \
            case-insensitive on the path.
            """
        )
        var baseline: String?

        @Option(
            name: .long,
            help: """
            Path to a text file containing one URL per line. Each URL is \
            enqueued at depth 0; the crawler follows links from each up to \
            --max-depth, so set --max-depth 0 to fetch only the listed URLs \
            with no descent, --max-depth 3 to follow 3 levels of children, etc. \
            Useful for fetching a fixed list — e.g. URLs another corpus has \
            but this one is missing — without re-spidering everything. Lines \
            starting with '#' and blank lines are ignored.
            """
        )
        var urls: String?

        @Option(
            name: .long,
            help: """
            Discovery mode: \
            auto (default — JSON API primary, WKWebView fallback when JSON 404s), \
            json-only (JSON only, no WKWebView fallback — fastest, narrowest), \
            webview-only (WKWebView for everything — slowest, broadest discovery, \
            matches pre-2025-11-30 behavior).
            """
        )
        var discoveryMode: Shared.Configuration.DiscoveryMode = .auto

        @Flag(name: .long, inversion: .prefixedNo, help: "Only download accepted/implemented proposals (evolution type only)")
        var onlyAccepted: Bool = true

        @Option(name: .long, help: "Maximum number of items to fetch (packages/code types only)")
        var limit: Int?

        @Flag(name: .long, help: "Use fast mode (higher concurrency, shorter timeout) for availability fetch")
        var fast: Bool = false

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: .hidden
        )
        var recurse: Bool = true

        @Flag(
            name: .long,
            help: .hidden
        )
        var refresh: Bool = false

        @Flag(
            name: .long,
            help: "Skip the Swift Package Index metadata refresh stage of `--type packages` (run only the archive download)."
        )
        var skipMetadata: Bool = false

        @Flag(
            name: .long,
            help: "Skip the GitHub archive download stage of `--type packages` (run only the metadata refresh)."
        )
        var skipArchives: Bool = false

        @Flag(
            name: .long,
            help: """
            After `--type packages` stage 2, walk the on-disk corpus and \
            write a per-package `availability.json` recording \
            `Package.swift` deployment targets and every `@available(...)` \
            attribute in `Sources/` and `Tests/`. Pure on-disk pass — no network. Idempotent.
            """
        )
        var annotateAvailability: Bool = false

        mutating func run() async throws {
            // #781: invocation banner before any other work.
            Cupertino.Context.composition.logging.logInvocation()

            logStartMessage()

            // Post-#1031 (Phase 1I.c.2 of epic #1007): dispatch on
            // canonical source-id strings instead of the dissolved
            // FetchType enum. Special tokens: "all" (iterate all
            // fetchable sources sequentially), "availability"
            // (maintenance op, not a registry source).
            switch source {
            case "all":
                try await runAllFetches()
            case Shared.Constants.SourcePrefix.packages:
                try await runPackageFetch()
            case Shared.Constants.SourcePrefix.appleSampleCode:
                try await runCodeFetch()
            case Shared.Constants.SourcePrefix.samples:
                try await runSamplesFetch()
            case Shared.Constants.SourcePrefix.appleArchive:
                try await runArchiveCrawl()
            case Shared.Constants.SourcePrefix.hig:
                try await runHIGCrawl()
            case "availability":
                try await runAvailabilityFetch()
            case Shared.Constants.SourcePrefix.swiftEvolution:
                try await runEvolutionCrawl()
            case Shared.Constants.SourcePrefix.appleDocs, Shared.Constants.SourcePrefix.swiftOrg:
                // Web-crawl fall-through: apple-docs + swift-org.
                try await runStandardCrawl()
            default:
                throw ValidationError(
                    "Unknown --source value '\(source)'. Valid sources: apple-docs, swift-org, swift-evolution, packages, apple-sample-code, samples, apple-archive, hig, availability, all."
                )
            }
        }

        private func logStartMessage() {
            // The Crawler auto-resumes whenever metadata.json's crawlState is active
            // and matches the start URL — no flag needed. We log "Fetching" here
            // unconditionally; the Crawler itself prints "🔄 Found resumable session"
            // when it actually loads saved state.
            Cupertino.Context.composition.logging.recording.info("🚀 Cupertino - Fetching \(Self.displayName(forSource: source))")
            // Print the resolved output directory at startup so #212-style
            // BinaryConfig misrouting is immediately visible.
            let resolvedOutputDir = outputDir.flatMap { URL(fileURLWithPath: $0).expandingTildeInPath.path }
                ?? Self.defaultOutputDir(forSource: source, paths: Shared.Paths.live())
            Cupertino.Context.composition.logging.recording.info("   Output: \(resolvedOutputDir)\n")
        }

        /// Post-#1031 (Phase 1I.c.2): canonical sourceID list for the
        /// `--source all` iteration. Includes the 8 registry source-ids
        /// plus the two special tokens that aren't in the registry
        /// (`apple-sample-code` legacy bundle + `availability`
        /// maintenance op). `apple-sample-code` is omitted from
        /// `--source all` because it overlaps with the GitHub-based
        /// `samples` and would double-fetch (matches the pre-#1031
        /// FetchType.allTypes which split `.code` and `.samples` into
        /// directFetchTypes but the all-iteration is over both).
        private static let allFetchableSources: [String] = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.packages,
            Shared.Constants.SourcePrefix.appleSampleCode,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            "availability",
        ]

        /// Lookup the user-facing display name for a source-id. For
        /// registered providers, reads from the registry's FetchInfo;
        /// for special tokens (`all`, `availability`,
        /// `apple-sample-code`), uses hardcoded labels.
        private static func displayName(forSource source: String) -> String {
            // Special tokens (not in the registry).
            switch source {
            case "all": return Shared.Constants.DisplayName.allDocs
            case "availability": return "API Availability Data"
            default:
                break
            }
            // Registered providers.
            if let provider = CLIImpl.makeProductionSourceRegistry().allEnabled.first(where: { $0.definition.id == source }) {
                return provider.fetchInfo?.displayName ?? provider.definition.displayName
            }
            return source
        }

        /// Lookup the default output directory for a source-id.
        /// Source-ids that map to a registered provider's FetchInfo
        /// resolve their `defaultOutputDirKey` against `Shared.Paths`;
        /// the special tokens are mapped directly.
        private static func defaultOutputDir(forSource source: String, paths: Shared.Paths) -> String {
            switch source {
            case "all":
                return paths.baseDirectory.path
            case "availability":
                return paths.docsDirectory.path
            default:
                break
            }
            guard let provider = CLIImpl.makeProductionSourceRegistry().allEnabled.first(where: { $0.definition.id == source }),
                  let key = provider.fetchInfo?.defaultOutputDirKey else {
                return paths.baseDirectory.path
            }
            return resolveDirectory(forKey: key, paths: paths).path
        }

        /// Map a `Search.FetchInfo.DefaultOutputDirKey` to the matching
        /// `Shared.Paths` accessor URL. (See `Search.FetchInfo.DefaultOutputDirKey`
        /// in `SearchModels/Search.FetchInfo.swift` for the canonical
        /// 8-case enum.) `SearchModels.Search` fully qualifies the
        /// namespace because `Search` resolves to
        /// `CLIImpl.Command.Search` inside `extension CLIImpl.Command`.
        private static func resolveDirectory(forKey key: SearchModels.Search.FetchInfo.DefaultOutputDirKey, paths: Shared.Paths) -> URL {
            switch key {
            case .docs: return paths.docsDirectory
            case .swiftOrg: return paths.swiftOrgDirectory
            case .swiftEvolution: return paths.swiftEvolutionDirectory
            case .packages: return paths.packagesDirectory
            case .sampleCode: return paths.sampleCodeDirectory
            case .archive: return paths.archiveDirectory
            case .hig: return paths.higDirectory
            case .baseDirectory: return paths.baseDirectory
            }
        }

        private mutating func runAllFetches() async throws {
            Cupertino.Context.composition.logging.recording.info("📚 Fetching all documentation types in parallel:\n")
            let baseCommand = self

            try await withThrowingTaskGroup(of: (String, Result<Void, Error>).self) { group in
                for sourceID in Self.allFetchableSources {
                    group.addTask {
                        await Self.fetchSingleSource(sourceID, baseCommand: baseCommand)
                    }
                }

                let results = try await collectFetchResults(from: &group)
                try validateFetchResults(results)
            }
        }

        private static func fetchSingleSource(
            _ sourceID: String,
            baseCommand: CLIImpl.Command.Fetch
        ) async -> (String, Result<Void, Error>) {
            Cupertino.Context.composition.logging.recording.info("🚀 Starting \(displayName(forSource: sourceID))...")
            var fetchCommand = baseCommand
            fetchCommand.source = sourceID
            fetchCommand.outputDir = defaultOutputDir(forSource: sourceID, paths: Shared.Paths.live())

            do {
                try await fetchCommand.run()
                return (sourceID, .success(()))
            } catch {
                return (sourceID, .failure(error))
            }
        }

        private func collectFetchResults(
            from group: inout ThrowingTaskGroup<(String, Result<Void, Error>), Error>
        ) async throws -> [(String, Result<Void, Error>)] {
            var results: [(String, Result<Void, Error>)] = []
            for try await result in group {
                results.append(result)
                let (sourceID, outcome) = result
                switch outcome {
                case .success:
                    Cupertino.Context.composition.logging.recording.info("✅ Completed \(Self.displayName(forSource: sourceID))")
                case .failure(let error):
                    Cupertino.Context.composition.logging.recording.error("❌ Failed \(Self.displayName(forSource: sourceID)): \(error)")
                }
            }
            return results
        }

        private func validateFetchResults(_ results: [(String, Result<Void, Error>)]) throws {
            let failures = results.filter {
                if case .failure = $0.1 { return true }
                return false
            }

            if failures.isEmpty {
                Cupertino.Context.composition.logging.recording.info("\n✅ All documentation types fetched successfully!")
            } else {
                Cupertino.Context.composition.logging.recording.info("\n⚠️  Completed with \(failures.count) failure(s)")
                throw ExitCode.failure
            }
        }

        private mutating func runStandardCrawl() async throws {
            let url = try validateStartURL()
            let outputDirectory = try await determineOutputDirectory(for: url)
            if startClean {
                try Ingest.Session.clearSavedSession(at: outputDirectory, logger: Cupertino.Context.composition.logging.recording)
            }
            if retryErrors {
                try Ingest.Session.requeueErroredURLs(at: outputDirectory, maxDepth: maxDepth, logger: Cupertino.Context.composition.logging.recording)
            }
            if let baselinePath = baseline {
                let baselineURL = URL(fileURLWithPath: baselinePath).expandingTildeInPath
                try Ingest.Session.requeueFromBaseline(at: outputDirectory, baselineDir: baselineURL, maxDepth: maxDepth, logger: Cupertino.Context.composition.logging.recording)
            }
            if let urlsPath = urls {
                let urlsURL = URL(fileURLWithPath: urlsPath).expandingTildeInPath
                try Ingest.Session.enqueueURLsFromFile(
                    at: outputDirectory,
                    urlsFile: urlsURL,
                    maxDepth: maxDepth,
                    startURL: url,
                    logger: Cupertino.Context.composition.logging.recording
                )
            }
            let config = createConfiguration(url: url, outputDirectory: outputDirectory)
            try await executeCrawl(with: config)
        }

        // clearSavedSession lifted to Ingest.Session.clearSavedSession (#247)

        // requeueErroredURLs lifted to Ingest.Session.requeueErroredURLs (#247)

        // Inject URLs from a known-good baseline corpus that aren't in the
        // current crawl's known set (queue ∪ visited ∪ pages keys). Comparison
        // is case-insensitive on the URL path so the broken-extractor's
        // case-mixed output still matches the baseline's casing.
        //
        // `baselineDir` should point at the `docs/` subtree of a prior corpus
        // (e.g. `~/Developer/.../cupertino-docs/docs`). Each file's `.url` field
        // is read; URLs not in the current set are prepended to the queue at
        // `maxDepth` so the resumed crawl doesn't re-discover their children
        // (which the baseline already crawled).
        //
        // requeueFromBaseline lifted to Ingest.Session.requeueFromBaseline (#247)

        // Enqueue every URL listed in `urlsFile` (one URL per line) at
        // depth 0. The crawler then follows each URL's outgoing links up
        // to `maxDepth`, so the caller can use `--max-depth` to control
        // how deep the descent tree goes (`--max-depth 0` = no descent,
        // just fetch the listed URLs themselves). Lines starting with `#`
        // and blank lines are ignored. Initialises `crawlState` if missing
        // so the helper works against a fresh corpus too. (#210)
        //
        // enqueueURLsFromFile + collectBaselineURLs + lowercaseDocPath all lifted
        // to Ingest.Session in #247.

        private func validateStartURL() throws -> URL {
            let urlString = startURL ?? Self.defaultCrawlBaseURL(forSource: source)
            guard let url = URL(string: urlString) else {
                throw ValidationError("Invalid start URL: \(urlString)")
            }
            return url
        }

        /// Map a source-id to the canonical crawl base URL. For
        /// registered providers reads `fetchInfo.crawlBaseURLs.first`;
        /// returns empty string for non-web-crawl sources (matches the
        /// pre-#1031 `FetchType.defaultURL` switch arms).
        private static func defaultCrawlBaseURL(forSource source: String) -> String {
            // Registered providers.
            if let provider = CLIImpl.makeProductionSourceRegistry().allEnabled.first(where: { $0.definition.id == source }) {
                return provider.fetchInfo?.crawlBaseURLs.first ?? ""
            }
            return ""
        }

        /// Map a source-id to its default URL-prefix allowlist for the
        /// crawler. Returns the full `fetchInfo.crawlBaseURLs` array
        /// (swift-org spans www.swift.org + docs.swift.org); returns
        /// nil for sources that should auto-detect from the start URL
        /// (matches the pre-#1031 `FetchType.defaultAllowedPrefixes`
        /// switch shape).
        private static func defaultAllowedPrefixes(forSource source: String) -> [String]? {
            guard source == Shared.Constants.SourcePrefix.swiftOrg else {
                // Auto-detect from start URL for non-swift-org sources.
                return nil
            }
            // swift-org needs explicit prefixes covering both www.swift.org
            // and docs.swift.org (swift-book content lives under the latter).
            return [
                Shared.Constants.BaseURL.swiftOrg,
                Shared.Constants.BaseURL.swiftBook,
            ]
        }

        private func determineOutputDirectory(for url: URL) async throws -> URL {
            if let outputDir {
                return URL(fileURLWithPath: outputDir).expandingTildeInPath
            }
            return try await findExistingSession(for: url)
                ?? URL(fileURLWithPath: Self.defaultOutputDir(forSource: source, paths: Shared.Paths.live())).expandingTildeInPath
        }

        private func findExistingSession(for url: URL) async throws -> URL? {
            // Path-DI composition sub-root (#535).
            let paths = Shared.Paths.live()
            let candidates = [
                paths.docsDirectory,
                paths.swiftOrgDirectory,
                paths.swiftBookDirectory,
            ]

            for candidate in candidates {
                if let sessionDir = Ingest.Session.checkForSession(at: candidate, matching: url, logger: Cupertino.Context.composition.logging.recording) {
                    return sessionDir
                }
            }

            return try await scanCupertinoDirectory(for: url)
        }

        // checkForSession lifted to Ingest.Session.checkForSession (#247)

        private func scanCupertinoDirectory(for url: URL) async throws -> URL? {
            let cupertinoDir = Shared.Paths.live().baseDirectory

            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: cupertinoDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            for dir in contents {
                let isDirectory = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
                guard isDirectory == true else {
                    continue
                }
                if let sessionDir = Ingest.Session.checkForSession(at: dir, matching: url, logger: Cupertino.Context.composition.logging.recording) {
                    return sessionDir
                }
            }

            return nil
        }

        private func createConfiguration(
            url: URL,
            outputDirectory: URL
        ) -> Shared.Configuration {
            // Use user-provided prefixes, or fall back to source defaults
            // (swift-org spans www.swift.org + docs.swift.org per the
            // pre-#1031 FetchType.swift.defaultAllowedPrefixes arm).
            let prefixes: [String]? = allowedPrefixes?
                .split(separator: ",")
                .map { String($0.trimmingCharacters(in: .whitespaces)) }
                ?? Self.defaultAllowedPrefixes(forSource: source)

            return Shared.Configuration(
                crawler: Shared.Configuration.Crawler(
                    startURL: url,
                    allowedPrefixes: prefixes,
                    maxPages: maxPages,
                    maxDepth: maxDepth,
                    outputDirectory: outputDirectory,
                    discoveryMode: discoveryMode
                ),
                changeDetection: Shared.Configuration.ChangeDetection(
                    forceRecrawl: force,
                    outputDirectory: outputDirectory
                ),
                output: Shared.Configuration.Output(format: .markdown)
            )
        }

        private func executeCrawl(with config: Shared.Configuration) async throws {
            // GoF Strategy (1994 p. 315): the crawler's three injected
            // algorithms (HTML → structured page, Apple-JSON → markdown,
            // priority-package catalog generation) are constructed here,
            // at the fetch command's composition sub-root. Each Live
            // struct is stateless, so per-call construction is the right
            // shape — Singleton (p. 127) would only be appropriate if a
            // single-instance invariant mattered, which it doesn't here.
            let htmlParser: any Crawler.HTMLParserStrategy = LiveHTMLParserStrategy()
            let appleJSONParser: any Crawler.AppleJSONParserStrategy = LiveAppleJSONParserStrategy()
            let priorityPackageStrategy: any Crawler.PriorityPackageStrategy = LivePriorityPackageStrategy()
            // GoF Strategy seam for log emission (1994 p. 315). The
            // Crawler target imports only LoggingModels (the protocol
            // surface); the production OSLog + console + file conformer
            // is wired here at the composition sub-root.
            let logger: any LoggingModels.Logging.Recording = Cupertino.Context.composition.logging.recording

            let crawler = await Crawler.AppleDocs(
                configuration: config,
                htmlParser: htmlParser,
                appleJSONParser: appleJSONParser,
                priorityPackageStrategy: priorityPackageStrategy,
                fetcherFactory: Crawler.WebKit.LiveHTTPFetcherFactory(),
                logger: logger
            )
            let stats = try await crawler.crawl(progress: AppleDocsCrawlProgressObserver(
                recording: Cupertino.Context.composition.logging.recording
            ))

            logCrawlCompletion(stats)
        }

        /// Closure-free observer for the Apple-docs crawl that prints
        /// per-URL progress lines through the binary's recorder. Replaces
        /// the previous trailing-closure pattern.
        private struct AppleDocsCrawlProgressObserver: Crawler.AppleDocsProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Crawler.AppleDocsProgress) {
                let percentage = String(format: "%.1f", progress.percentage)
                let urlComponent = progress.currentURL.lastPathComponent
                recording.output("   Progress: \(percentage)% - \(urlComponent)")
            }
        }

        private func logCrawlCompletion(_ stats: Shared.Models.CrawlStatistics) {
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Crawl completed!")
            Cupertino.Context.composition.logging.recording.info("   Total: \(stats.totalPages) pages")
            Cupertino.Context.composition.logging.recording.info("   New: \(stats.newPages)")
            Cupertino.Context.composition.logging.recording.info("   Updated: \(stats.updatedPages)")
            Cupertino.Context.composition.logging.recording.info("   Skipped: \(stats.skippedPages)")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
        }

        private func runEvolutionCrawl() async throws {
            let defaultPath = Shared.Paths.live().swiftEvolutionDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath
            let logger: any LoggingModels.Logging.Recording = Cupertino.Context.composition.logging.recording

            let crawler = await Crawler.Evolution(
                outputDirectory: outputURL,
                onlyAccepted: onlyAccepted,
                logger: logger
            )

            let stats = try await crawler.crawl(progress: EvolutionCrawlProgressObserver(
                recording: Cupertino.Context.composition.logging.recording
            ))

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Download completed!")
            Cupertino.Context.composition.logging.recording.info("   Total: \(stats.totalProposals) proposals")
            Cupertino.Context.composition.logging.recording.info("   New: \(stats.newProposals)")
            Cupertino.Context.composition.logging.recording.info("   Updated: \(stats.updatedProposals)")
            Cupertino.Context.composition.logging.recording.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
        }

        /// `--type packages` — runs metadata refresh then archive download in
        /// sequence. Either stage can be skipped via `--skip-metadata` /
        /// `--skip-archives`. The two were separate fetch types until #217;
        /// merged because they always ran back-to-back, shared the output dir,
        /// and the `package-docs` name was misleading (it fetches whole archives,
        /// not READMEs). Stage 2 reads `Core.PackageIndexing.PriorityPackagesCatalog`, not the
        /// metadata catalog, so the stages are independent.
        private func runPackageFetch() async throws {
            let defaultPath = Shared.Paths.live().packagesDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            if skipMetadata, skipArchives, !annotateAvailability {
                Cupertino.Context.composition.logging.recording.error(
                    "❌ Both --skip-metadata and --skip-archives passed without --annotate-availability — nothing to do."
                )
                throw ExitCode.failure
            }

            if ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.githubToken] == nil {
                Cupertino.Context.composition.logging.recording.info(Shared.Constants.Message.gitHubTokenTip)
                Cupertino.Context.composition.logging.recording.info("   \(Shared.Constants.Message.rateLimitWithoutToken)")
                Cupertino.Context.composition.logging.recording.info("   \(Shared.Constants.Message.rateLimitWithToken)")
                Cupertino.Context.composition.logging.recording.info("   \(Shared.Constants.Message.exportGitHubToken)\n")
            }

            if !skipMetadata {
                try await runPackageMetadataStage(outputURL: outputURL)
            } else {
                Cupertino.Context.composition.logging.recording.info("⏭  --skip-metadata: skipping Swift Package Index metadata refresh")
            }

            if !skipArchives {
                try await runPackageArchivesStage(outputURL: outputURL)
            } else {
                Cupertino.Context.composition.logging.recording.info("⏭  --skip-archives: skipping GitHub archive download")
            }

            if annotateAvailability {
                try await runPackageAnnotationStage(outputURL: outputURL)
            }
        }

        /// Stage 3 (#219): walk every `<owner>/<repo>/` subdir under `outputURL`
        /// and write `availability.json` capturing `Package.swift` deployment
        /// targets and every `@available(...)` attribute occurrence in the
        /// `Sources/` and `Tests/` trees. Pure on-disk pass — runs whether or
        /// not stage 2 just downloaded fresh archives. Idempotent.
        private func runPackageAnnotationStage(outputURL: URL) async throws {
            Cupertino.Context.composition.logging.recording.info("🏷  Stage 3 — Annotating availability metadata (#219)")

            let fm = FileManager.default
            guard fm.fileExists(atPath: outputURL.path) else {
                Cupertino.Context.composition.logging.recording.error(
                    "❌ Packages directory \(outputURL.path) doesn't exist — run with stage 2 first."
                )
                throw ExitCode.failure
            }

            let owners = (try? Shared.Utils.FileSystem.contentsOfDirectory(at: outputURL, includingPropertiesForKeys: nil))?
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                ?? []

            let annotator = Core.PackageIndexing.PackageAvailabilityAnnotator()
            var packagesAnnotated = 0
            var totalAttrs = 0
            let startedAt = Date()

            for ownerURL in owners.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let repos = (try? Shared.Utils.FileSystem.contentsOfDirectory(at: ownerURL, includingPropertiesForKeys: nil))?
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .filter { !$0.lastPathComponent.hasPrefix(".") }
                    ?? []

                for repoURL in repos.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let label = "\(ownerURL.lastPathComponent)/\(repoURL.lastPathComponent)"
                    do {
                        let result = try await annotator.annotate(packageDirectory: repoURL)
                        packagesAnnotated += 1
                        totalAttrs += result.stats.totalAttributes
                        Cupertino.Context.composition.logging.recording.info(
                            "  ✅ \(label) — \(result.stats.totalAttributes) @available attrs across "
                                + "\(result.stats.filesWithAvailability)/\(result.stats.filesScanned) files"
                        )
                    } catch {
                        Cupertino.Context.composition.logging.recording.error("  ✗ \(label) — \(error.localizedDescription)")
                    }
                }
            }

            let duration = Int(Date().timeIntervalSince(startedAt))
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Annotation completed")
            Cupertino.Context.composition.logging.recording.info("   Packages annotated: \(packagesAnnotated)")
            Cupertino.Context.composition.logging.recording.info("   Total @available attrs: \(totalAttrs)")
            Cupertino.Context.composition.logging.recording.info("   Duration: \(duration)s")
        }

        private func runPackageMetadataStage(outputURL: URL) async throws {
            Cupertino.Context.composition.logging.recording.info("📇 Stage 1/2 — Refreshing Swift Package Index metadata")

            let fetcher = Core.PackageIndexing.PackageFetcher(
                outputDirectory: outputURL,
                limit: limit,
                resume: !startClean,
                logger: Cupertino.Context.composition.logging.recording
            )

            let stats = try await fetcher.fetch(progress: PackageFetcherProgressObserver(
                recording: Cupertino.Context.composition.logging.recording
            ))

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Metadata refresh completed")
            Cupertino.Context.composition.logging.recording.info("   Total packages: \(stats.totalPackages)")
            Cupertino.Context.composition.logging.recording.info("   Successful: \(stats.successfulFetches)")
            Cupertino.Context.composition.logging.recording.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
            Cupertino.Context.composition.logging.recording.info("   📁 \(outputURL.path)/\(Shared.Constants.FileName.packagesWithStars)\n")
        }

        // #673 Phase D iter-5: 174-line body — Stage 2 of the
        // packages fetch: priority-catalog load → resolve → per-archive
        // download → magic-bytes validation → on-disk catalog write →
        // skip-statistics accounting. Linear pipeline; helpers would
        // need to pass a 6-tuple of state to be useful.
        // swiftlint:disable:next function_body_length
        private func runPackageArchivesStage(outputURL: URL) async throws {
            Cupertino.Context.composition.logging.recording.info("📦 Stage 2/2 — Downloading priority package archives")

            // Path-DI arc (#535): construct a `Shared.Paths` at the
            // function's composition sub-root and pass explicit URLs.
            let paths = Shared.Paths.live()

            // Construct the priority-packages catalog with the resolved
            // base directory (#535: catalog is now an actor, not a singleton).
            let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(baseDirectory: paths.baseDirectory)

            // Load priority packages
            let priorityPackages = await priorityCatalog.allPackages

            guard !priorityPackages.isEmpty else {
                let priorityPackagesPath = paths.packagesDirectory
                    .appendingPathComponent(Shared.Constants.FileName.priorityPackages)
                    .path
                Cupertino.Context.composition.logging.recording.error("❌ Error: No priority packages found")
                Cupertino.Context.composition.logging.recording.error("   Searched:")
                Cupertino.Context.composition.logging.recording.error("   - \(priorityPackagesPath)")
                Cupertino.Context.composition.logging.recording.error("   - Shared.Constants.CriticalApplePackages")
                Cupertino.Context.composition.logging.recording.error("   - Shared.Constants.KnownEcosystemPackages")
                Cupertino.Context.composition.logging.recording.error("\n   Please ensure at least one package source is configured.")
                throw ExitCode.failure
            }

            // Convert to PackageReference format
            let seedRefs = priorityPackages.compactMap { pkg -> Shared.Models.PackageReference? in
                // Extract owner from URL if not provided
                let owner: String
                if let explicitOwner = pkg.owner, !explicitOwner.isEmpty {
                    owner = explicitOwner
                } else {
                    // Parse from GitHub URL: https://github.com/owner/repo
                    guard let url = URL(string: pkg.url) else {
                        return nil
                    }
                    let pathComponents = Array(url.pathComponents.dropFirst())
                    guard pathComponents.count >= 2 else {
                        return nil
                    }
                    owner = pathComponents[0]
                }

                let isApple = owner == Shared.Constants.GitHubOrg.apple
                    || owner == Shared.Constants.GitHubOrg.swiftlang
                    || owner == Shared.Constants.GitHubOrg.swiftServer
                return Shared.Models.PackageReference(
                    owner: owner,
                    repo: pkg.repo,
                    url: pkg.url,
                    priority: isApple ? .appleOfficial : .ecosystem
                )
            }

            let exclusions = Core.PackageIndexing.ExclusionList.load(from: paths.baseDirectory)
            let seedChecksum = Core.PackageIndexing.ResolvedPackagesStore.checksum(seeds: seedRefs, exclusions: exclusions)
            let resolvedStoreURL = paths.baseDirectory
                .appendingPathComponent(Shared.Constants.FileName.resolvedPackages)
            let canonicalCacheURL = paths.baseDirectory
                .appendingPathComponent(".cache")
                .appendingPathComponent(Shared.Constants.FileName.canonicalOwnersCache)

            let resolvedPackages: [Core.PackageIndexing.ResolvedPackage]
            if recurse {
                if !refresh,
                   let cached = Core.PackageIndexing.ResolvedPackagesStore.load(from: resolvedStoreURL),
                   cached.seedChecksum == seedChecksum {
                    Cupertino.Context.composition.logging.recording
                        .info("🔗 Using cached closure from resolved-packages.json (\(cached.packages.count) packages, generated \(cached.generatedAt))")
                    resolvedPackages = cached.packages
                } else {
                    if refresh {
                        Cupertino.Context.composition.logging.recording.info("🔗 --refresh: discarding cached closure, re-walking dependency graphs...")
                    } else {
                        Cupertino.Context.composition.logging.recording.info("🔗 Resolving transitive dependencies for \(seedRefs.count) seed packages...")
                    }
                    if !exclusions.isEmpty {
                        Cupertino.Context.composition.logging.recording.info("   Exclusion list in effect: \(exclusions.count) entries")
                    }
                    let canonicalizer = Core.PackageIndexing.GitHubCanonicalizer(cacheURL: canonicalCacheURL)
                    let manifestCache = Core.PackageIndexing.ManifestCache(
                        rootDirectory: paths.baseDirectory
                            .appendingPathComponent(".cache")
                            .appendingPathComponent("manifests")
                    )
                    let resolver = Core.PackageIndexing.PackageDependencyResolver(
                        canonicalizer: canonicalizer,
                        exclusions: exclusions,
                        manifestCache: manifestCache
                    )
                    let (resolved, resolverStats) = await resolver.resolve(
                        seeds: seedRefs,
                        progress: PackageDependencyResolverProgressObserver(
                            recording: Cupertino.Context.composition.logging.recording
                        )
                    )
                    resolvedPackages = resolved
                    Cupertino.Context.composition.logging.recording.info("   Seeds: \(resolverStats.seedCount)")
                    Cupertino.Context.composition.logging.recording.info("   Discovered via dependencies: \(resolverStats.discoveredCount)")
                    Cupertino.Context.composition.logging.recording.info("   Excluded: \(resolverStats.excludedCount)")
                    Cupertino.Context.composition.logging.recording.info("   Skipped (non-GitHub): \(resolverStats.skippedNonGitHub)")
                    Cupertino.Context.composition.logging.recording.info("   Skipped (SPM registry id): \(resolverStats.skippedRegistry)")
                    Cupertino.Context.composition.logging.recording.info("   Missing manifest: \(resolverStats.missingManifest)")
                    Cupertino.Context.composition.logging.recording.info("   Malformed manifest: \(resolverStats.malformedManifest)")
                    Cupertino.Context.composition.logging.recording.info("   Resolver duration: \(Int(resolverStats.duration))s")

                    let store = Core.PackageIndexing.ResolvedPackagesStore(
                        cupertinoVersion: Shared.Constants.App.version,
                        seedChecksum: seedChecksum,
                        packages: resolved
                    )
                    do {
                        try store.write(to: resolvedStoreURL)
                        Cupertino.Context.composition.logging.recording.info("   Saved closure to \(resolvedStoreURL.path)")
                    } catch {
                        Cupertino.Context.composition.logging.recording.error("   ⚠️  Could not persist resolved-packages.json: \(error)")
                    }
                }
            } else {
                resolvedPackages = seedRefs.map { ref in
                    Core.PackageIndexing.ResolvedPackage(
                        owner: ref.owner,
                        repo: ref.repo,
                        url: ref.url,
                        priority: ref.priority,
                        parents: ["\(ref.owner.lowercased())/\(ref.repo.lowercased())"]
                    )
                }
                Cupertino.Context.composition.logging.recording.info("🔗 Skipping dependency resolution (--no-recurse)")
                if !exclusions.isEmpty {
                    Cupertino.Context.composition.logging.recording.info("   Exclusion list ignored while --no-recurse is set")
                }
            }

            Cupertino.Context.composition.logging.recording.info("📦 Fetching \(resolvedPackages.count) archives into \(outputURL.path)...")

            let extractor = Core.PackageIndexing.PackageArchiveExtractor()
            let startedAt = Date()
            var stats = Shared.Models.PackageDownloadStatistics(
                totalPackages: resolvedPackages.count,
                startTime: startedAt
            )
            for (idx, pkg) in resolvedPackages.enumerated() {
                let label = "\(pkg.owner)/\(pkg.repo)"
                let pkgDir = outputURL
                    .appendingPathComponent(pkg.owner)
                    .appendingPathComponent(pkg.repo)
                do {
                    let extraction = try await extractor.fetchAndExtract(
                        owner: pkg.owner,
                        repo: pkg.repo,
                        destination: pkgDir
                    )
                    try writePackageManifest(
                        resolved: pkg,
                        extraction: extraction,
                        destination: pkgDir
                    )
                    stats.newPackages += 1
                    stats.totalFilesSaved += extraction.files.count
                    stats.totalBytesSaved += extraction.totalBytes
                    let kb = extraction.totalBytes / 1024
                    Cupertino.Context.composition.logging.recording.info("  ✅ \(label) — \(extraction.files.count) files, \(kb) KB")
                } catch Core.PackageIndexing.PackageArchiveExtractor.ExtractError.tarballNotFound {
                    stats.errors += 1
                    Cupertino.Context.composition.logging.recording.error("  ✗ \(label) — archive not found on any ref")
                } catch Core.PackageIndexing.PackageArchiveExtractor.ExtractError.tarballTooLarge(let bytes) {
                    stats.errors += 1
                    Cupertino.Context.composition.logging.recording.error("  ✗ \(label) — archive too large (\(bytes / 1024 / 1024) MB)")
                } catch {
                    stats.errors += 1
                    Cupertino.Context.composition.logging.recording.error("  ✗ \(label) — \(error.localizedDescription)")
                }

                if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 || idx + 1 == resolvedPackages.count {
                    let percent = Double(idx + 1) / Double(resolvedPackages.count) * 100
                    Cupertino.Context.composition.logging.recording.output(
                        String(format: "📊 Progress: %.1f%% (%d/%d)", percent, idx + 1, resolvedPackages.count)
                    )
                }
            }
            stats.endTime = Date()

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Archive download completed")
            Cupertino.Context.composition.logging.recording.info("   New packages: \(stats.newPackages)")
            Cupertino.Context.composition.logging.recording.info("   Files saved: \(stats.totalFilesSaved)")
            Cupertino.Context.composition.logging.recording.info("   Bytes saved: \(stats.totalBytesSaved / 1024) KB")
            Cupertino.Context.composition.logging.recording.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
            Cupertino.Context.composition.logging.recording.info("   📁 \(outputURL.path)")
            Cupertino.Context.composition.logging.recording.info("   Next: index them into \(paths.packagesDatabase.path) via `save --packages`")
        }

        private func writePackageManifest(
            resolved: Core.PackageIndexing.ResolvedPackage,
            extraction: Core.PackageIndexing.PackageExtractionResult,
            destination: URL
        ) throws {
            struct Manifest: Encodable {
                let owner: String
                let repo: String
                let url: String
                let fetchedAt: Date
                let cupertinoVersion: String
                let branch: String
                let parents: [String]
                let savedFileCount: Int
                let totalBytes: Int64
                let tarballBytes: Int
            }
            let manifest = Manifest(
                owner: resolved.owner,
                repo: resolved.repo,
                url: resolved.url,
                fetchedAt: Date(),
                cupertinoVersion: Shared.Constants.App.version,
                branch: extraction.branch,
                parents: resolved.parents,
                savedFileCount: extraction.files.count,
                totalBytes: extraction.totalBytes,
                tarballBytes: extraction.tarballBytes
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: destination.appendingPathComponent("manifest.json"))
        }

        /// Closure-free observer for the legacy code-fetch command that
        /// prints per-sample progress through the binary's recorder.
        /// Mirrors `GitHubFetcherProgressObserver` from #567.
        private struct DownloaderProgressObserver: Sample.Core.DownloaderProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Sample.Core.Progress) {
                let percent = String(format: "%.1f", progress.percentage)
                recording.output("   Progress: \(percent)% - \(progress.sampleName)")
            }
        }

        private func runCodeFetch() async throws {
            let defaultPath = Shared.Paths.live().sampleCodeDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            let recording = Cupertino.Context.composition.logging.recording
            let crawler = await Sample.Core.Downloader(
                outputDirectory: outputURL,
                maxSamples: limit,
                forceDownload: force, logger: recording
            )

            let observer = DownloaderProgressObserver(recording: recording)
            let stats = try await crawler.download(progress: observer)

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Download completed!")
            Cupertino.Context.composition.logging.recording.info("   Total: \(stats.totalSamples) samples")
            Cupertino.Context.composition.logging.recording.info("   Downloaded: \(stats.downloadedSamples)")
            Cupertino.Context.composition.logging.recording.info("   Skipped: \(stats.skippedSamples)")
            Cupertino.Context.composition.logging.recording.info("   Errors: \(stats.errors)")
            // #657 — surface the invalid-downloads bucket only when
            // non-zero so the happy-path output stays unchanged.
            if stats.invalidDownloads > 0 {
                Cupertino.Context.composition.logging.recording.info(
                    "   Invalid downloads (parked as .invalid): \(stats.invalidDownloads)"
                )
            }
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
        }

        /// Closure-free observer for the GitHub samples fetch. Forwards each
        /// `Sample.Core.GitHubFetcherProgress` message through the binary's
        /// recorder. Replaces the previous trailing-closure pattern.
        private struct GitHubFetcherProgressObserver: Sample.Core.GitHubFetcherProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Sample.Core.GitHubFetcherProgress) {
                recording.output("   \(progress.message)")
            }
        }

        private func runSamplesFetch() async throws {
            let defaultPath = Shared.Paths.live().sampleCodeDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

            let recording = Cupertino.Context.composition.logging.recording
            let fetcher = Sample.Core.GitHubFetcher(outputDirectory: outputURL, logger: recording)
            let observer = GitHubFetcherProgressObserver(recording: recording)

            let stats = try await fetcher.fetch(progress: observer)

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Fetch completed!")
            Cupertino.Context.composition.logging.recording.info("   Action: \(stats.action.description)")
            Cupertino.Context.composition.logging.recording.info("   Projects: \(stats.projectCount)")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
            Cupertino.Context.composition.logging.recording.info("\n📁 Output: \(outputURL.path)/cupertino-sample-code")
        }

        private func runArchiveCrawl() async throws {
            let defaultPath = Shared.Paths.live().archiveDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            // Load guides from bundled manifest or command line
            let guides = try await loadArchiveGuides()

            guard !guides.isEmpty else {
                Cupertino.Context.composition.logging.recording.error("❌ No archive guides configured")
                Cupertino.Context.composition.logging.recording.info("   Use --start-url to specify guide URLs or configure the manifest")
                throw ExitCode.failure
            }

            Cupertino.Context.composition.logging.recording.info("📚 Crawling \(guides.count) Apple Archive guides...")
            Cupertino.Context.composition.logging.recording.info("   Output: \(outputURL.path)\n")
            let logger: any LoggingModels.Logging.Recording = Cupertino.Context.composition.logging.recording

            let crawler = await Crawler.AppleArchive(
                outputDirectory: outputURL,
                guides: guides,
                forceRecrawl: force,
                logger: logger
            )

            let stats = try await crawler.crawl(progress: AppleArchiveCrawlProgressObserver(
                recording: Cupertino.Context.composition.logging.recording
            ))

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Crawl completed!")
            Cupertino.Context.composition.logging.recording.info("   Total guides: \(stats.totalGuides)")
            Cupertino.Context.composition.logging.recording.info("   Total pages: \(stats.totalPages)")
            Cupertino.Context.composition.logging.recording.info("   New: \(stats.newPages)")
            Cupertino.Context.composition.logging.recording.info("   Updated: \(stats.updatedPages)")
            Cupertino.Context.composition.logging.recording.info("   Skipped: \(stats.skippedPages)")
            Cupertino.Context.composition.logging.recording.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
            Cupertino.Context.composition.logging.recording.info("\n📁 Output: \(outputURL.path)/")
        }

        private func runHIGCrawl() async throws {
            let defaultPath = Shared.Paths.live().higDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            Cupertino.Context.composition.logging.recording.info("📖 Crawling Human Interface Guidelines...")
            Cupertino.Context.composition.logging.recording.info("   Output: \(outputURL.path)\n")
            let logger: any LoggingModels.Logging.Recording = Cupertino.Context.composition.logging.recording

            let crawler = await Crawler.HIG(
                outputDirectory: outputURL,
                forceRecrawl: force,
                fetcherFactory: Crawler.WebKit.LiveHTTPFetcherFactory(),
                logger: logger
            )

            let stats = try await crawler.crawl(progress: HIGCrawlProgressObserver(
                recording: Cupertino.Context.composition.logging.recording
            ))

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Crawl completed!")
            Cupertino.Context.composition.logging.recording.info("   Total pages: \(stats.totalPages)")
            Cupertino.Context.composition.logging.recording.info("   New: \(stats.newPages)")
            Cupertino.Context.composition.logging.recording.info("   Updated: \(stats.updatedPages)")
            Cupertino.Context.composition.logging.recording.info("   Skipped: \(stats.skippedPages)")
            Cupertino.Context.composition.logging.recording.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
            Cupertino.Context.composition.logging.recording.info("\n📁 Output: \(outputURL.path)/")
        }

        private func loadArchiveGuides() async throws -> [Crawler.AppleArchive.GuideInfo] {
            // If start URL is provided, use it (no framework info available)
            if let startURL, let url = URL(string: startURL) {
                return [Crawler.AppleArchive.GuideInfo(url: url, framework: "")]
            }

            // Otherwise use the curated list of essential archive guides with framework info
            return Crawler.ArchiveGuideCatalog.essentialGuidesWithInfo(
                baseDirectory: Shared.Paths.live().baseDirectory
            )
        }

        private func runAvailabilityFetch() async throws {
            let docsDir = outputDir.map { URL(fileURLWithPath: $0) }
                ?? Shared.Paths.live().docsDirectory

            guard FileManager.default.fileExists(atPath: docsDir.path) else {
                Cupertino.Context.composition.logging.recording.error("❌ Documentation directory not found: \(docsDir.path)")
                Cupertino.Context.composition.logging.recording.info("   Run 'cupertino fetch --type docs' first to download documentation.")
                throw ExitCode.failure
            }

            Cupertino.Context.composition.logging.recording.info("📊 Fetching API availability data...")
            Cupertino.Context.composition.logging.recording.info("   Source: \(docsDir.path)")
            Cupertino.Context.composition.logging.recording.info("   API: developer.apple.com/tutorials/data/documentation\n")

            let configuration: Availability.Fetcher.Configuration
            if fast {
                configuration = .fast
            } else {
                configuration = Availability.Fetcher.Configuration(
                    concurrency: 50,
                    timeout: 1.0,
                    skipExisting: !force
                )
            }

            let fetcher = Availability.Fetcher(
                docsDirectory: docsDir,
                configuration: configuration,
                networkingFactory: LiveAvailabilityNetworkingFactory()
            )

            let stats = try await fetcher.fetch { progress in
                let percent = String(format: "%.1f", progress.percentage)
                let successRate = progress.completed > 0
                    ? String(format: "%.0f", Double(progress.successful) / Double(progress.completed) * 100)
                    : "0"
                Cupertino.Context.composition.logging.recording.output(
                    "   Progress: \(percent)% [\(progress.currentFramework)] \(successRate)% success"
                )
            }

            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.info("✅ Availability fetch completed!")
            Cupertino.Context.composition.logging.recording.info("   Documents scanned: \(stats.totalDocuments)")
            Cupertino.Context.composition.logging.recording.info("   Updated: \(stats.updatedDocuments)")
            Cupertino.Context.composition.logging.recording.info("   Skipped: \(stats.skippedDocuments)")
            Cupertino.Context.composition.logging.recording.info("   Failed: \(stats.failedFetches)")
            Cupertino.Context.composition.logging.recording.info("   Frameworks: \(stats.frameworksProcessed)")
            Cupertino.Context.composition.logging.recording.info("   Success rate: \(String(format: "%.1f", stats.successRate))%")
            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(duration))s")
            }
        }

        /// Closure-free observer for Swift Evolution crawl progress.
        private struct EvolutionCrawlProgressObserver: Crawler.EvolutionProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Crawler.EvolutionProgress) {
                let percentage = String(format: "%.1f", progress.percentage)
                recording.output("   Progress: \(percentage)% - \(progress.proposalID)")
            }
        }

        /// Closure-free observer for Apple Archive crawl progress.
        private struct AppleArchiveCrawlProgressObserver: Crawler.AppleArchiveProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Crawler.AppleArchiveProgress) {
                let percent = String(format: "%.1f", progress.percentage)
                recording.output("   Progress: \(percent)% - \(progress.currentItem)")
            }
        }

        /// Closure-free observer for HIG crawl progress.
        private struct HIGCrawlProgressObserver: Crawler.HIGProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Crawler.HIGProgress) {
                let percent = String(format: "%.1f", progress.percentage)
                recording.output("   Progress: \(percent)% - \(progress.currentItem)")
            }
        }

        /// Closure-free observer for `Core.PackageIndexing.PackageFetcher`
        /// progress. Prints per-package progress lines through the
        /// binary's recorder. Replaces the previous trailing-closure
        /// pattern at the call site.
        private struct PackageFetcherProgressObserver: Core.PackageIndexing.PackageFetcherProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Core.PackageIndexing.PackageFetcherProgress) {
                let percent = String(format: "%.1f", progress.percentage)
                recording.output("   Progress: \(percent)% - \(progress.packageName)")
            }
        }

        /// Closure-free observer for
        /// `Core.PackageIndexing.PackageDependencyResolver` progress.
        /// Same throttled-output rule the previous trailing closure had
        /// (every 1, 10, total).
        private struct PackageDependencyResolverProgressObserver: Core.PackageIndexing.PackageDependencyResolverProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(packageName: String, processed: Int, total: Int) {
                if processed == 1 || processed % 10 == 0 || processed == total {
                    recording.output("   Resolving: \(processed)/\(total) (\(packageName))")
                }
            }
        }
    }
}

// FetchURLsError lifted to Ingest.FetchURLsError (#247)
