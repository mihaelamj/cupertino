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
import CrawlerModels
import CrawlerWebKit
import CupertinoComposition
import Foundation
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
    /// #673 Phase D iter-5: 916-line struct. ArgumentParser doesn't
    /// support partial-struct command composition, so every `@Option`
    /// / `@Flag` for every `--source` value must live on one struct.
    /// Post-#1031 (epic #1007 final step) the flag is `--source` keyed
    /// against canonical source-ids; pre-#1031 it was `--type` keyed
    /// against the dissolved `FetchType` enum's short names.
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

        @Option(name: .long, help: "Start URL to crawl from (overrides --source default)")
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
            help: "Skip the Swift Package Index metadata refresh stage of `--source packages` (run only the archive download)."
        )
        var skipMetadata: Bool = false

        @Flag(
            name: .long,
            help: "Skip the GitHub archive download stage of `--source packages` (run only the metadata refresh)."
        )
        var skipArchives: Bool = false

        @Flag(
            name: .long,
            help: """
            After `--source packages` stage 2, walk the on-disk corpus and \
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
            // 2026-05-26 audit Finding 9.7 + 11.1: dispatch via the
            // registered provider's `makeFetchStrategy()` for every
            // source that has a strategy. Special tokens (`"all"` /
            // `"availability"`) stay above the registry lookup
            // because they aren't registered providers — `"all"` is
            // a fan-out alias and `"availability"` is a maintenance
            // operation that refreshes the bundled SDK availability
            // data file (not a corpus source).
            //
            // The remaining 3 legacy switch arms (packages / samples
            // / apple-sample-code) are the complex multi-stage
            // handlers; they're queued for the same lift treatment
            // in a follow-up (per issue #1051). For NEW sources,
            // adding a `Search.SourceFetchStrategy` to the
            // `<X>Source` target is enough — zero edits here.
            switch source {
            case "all":
                try await runAllFetches()
            case "availability":
                try await runAvailabilityFetch()
            default:
                // 2026-05-26 audit Finding 9.7 + 11.1: every shipped
                // source (apple-docs / hig / apple-archive /
                // swift-evolution / swift-org / swift-book / samples /
                // apple-sample-code / packages) routes through the
                // registry dispatch via its `Search.SourceFetchStrategy`.
                // `apple-sample-code` is the legacy alias for `samples`;
                // both flow through `SampleCodeFetchStrategy`. Adding
                // a new source = zero edits to this switch.
                try await runRegistryFetchStrategy()
            }
        }

        /// 2026-05-26 audit Finding 9.7 + 11.1: registry-driven fetch
        /// dispatch. Resolves the source-id against the production
        /// registry, asks the provider for its `Search.SourceFetchStrategy`,
        /// and runs it with the CLI-supplied `FetchEnvironment`. The
        /// strategy concrete lives in the source's own SPM target
        /// (`<X>Source/<X>Source.FetchStrategy.swift`); CLI no longer
        /// owns the per-source fetch dispatch.
        private mutating func runRegistryFetchStrategy() async throws {
            let registry = CupertinoComposition.makeProductionSourceRegistry()
            // Canonicalize legacy `apple-sample-code` alias to `samples`
            // (SampleCodeSource's registered id) so the lookup hits.
            let canonicalSourceID = source == Shared.Constants.SourcePrefix.appleSampleCode
                ? Shared.Constants.SourcePrefix.samples
                : source
            guard let entry = registry.entry(for: canonicalSourceID) else {
                let validIDs = registry.allEnabled.map(\.definition.id).sorted()
                let validList = (["all", "availability"] + validIDs).joined(separator: ", ")
                throw ValidationError("Unknown --source value '\(source)'. Valid sources: \(validList).")
            }
            guard let strategy = entry.provider.makeFetchStrategy() else {
                throw ValidationError(
                    "Source '\(source)' has no fetch capability — its corpus arrives via "
                        + "`cupertino setup` or is co-crawled by another source. "
                        + "Try `cupertino fetch --source <X>` where X is one of the fetchable sources."
                )
            }
            let outputURL = try await resolveFetchOutputURL(for: entry.provider)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let env = await MainActor.run { makeFetchEnvironment(outputDirectory: outputURL) }
            try await strategy.run(env: env)
        }

        /// Resolve the output directory for a per-source fetch.
        /// Respects `--output-dir` when supplied; otherwise reads
        /// `provider.fetchInfo?.defaultOutputDirKey` and resolves
        /// against `Shared.Paths.live()`.
        private func resolveFetchOutputURL(for provider: any SearchModels.Search.SourceProvider) async throws -> URL {
            if let outputDir {
                return URL(fileURLWithPath: outputDir).expandingTildeInPath
            }
            let paths = Shared.Paths.live()
            guard let key = provider.fetchInfo?.defaultOutputDirKey else {
                // Provider has a fetch strategy but no fetchInfo dir
                // key — unusual but valid (the strategy could fetch
                // to a baseDirectory-relative location). Default to
                // baseDirectory.
                return paths.baseDirectory
            }
            return Self.resolveDirectory(forKey: key, paths: paths)
        }

        /// Build the `Search.FetchEnvironment` value passed to the
        /// per-source strategy. Reads every CLI flag once at the
        /// dispatch site; the strategy concretes pick out the fields
        /// they need and ignore the rest.
        @MainActor
        private func makeFetchEnvironment(outputDirectory: URL) -> SearchModels.Search.FetchEnvironment {
            let recording: any LoggingModels.Logging.Recording =
                Cupertino.Context.composition.logging.recording
            return SearchModels.Search.FetchEnvironment(
                outputDirectory: outputDirectory,
                maxPages: maxPages,
                maxDepth: maxDepth,
                force: force,
                startClean: startClean,
                retryErrors: retryErrors,
                baseline: baseline.map { URL(fileURLWithPath: $0).expandingTildeInPath },
                urls: urls.map { URL(fileURLWithPath: $0).expandingTildeInPath },
                startURL: startURL.flatMap { URL(string: $0) },
                allowedPrefixes: allowedPrefixes.map {
                    $0.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                },
                discoveryModeRawValue: discoveryMode.rawValue,
                onlyAccepted: onlyAccepted,
                limit: limit,
                skipMetadata: skipMetadata,
                skipArchives: skipArchives,
                annotateAvailability: annotateAvailability,
                recurse: recurse,
                refresh: refresh,
                fast: fast,
                logger: recording,
                httpFetcherFactory: Crawler.WebKit.LiveHTTPFetcherFactory(),
                htmlParser: LiveHTMLParserStrategy(),
                appleJSONParser: LiveAppleJSONParserStrategy(),
                priorityPackageStrategy: LivePriorityPackageStrategy()
            )
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
        /// `--source all` iteration. Mirrors pre-#1031
        /// `FetchType.allTypes` (which was `webCrawlTypes` +
        /// `directFetchTypes` covering 9 cases including BOTH `.code`
        /// and `.samples`). #1042 Cluster 8 sub-3: derived from
        /// the production source registry at call time. Every
        /// `Search.SourceProvider` with a non-nil `fetchInfo` ships a
        /// fetch leg; we add the `availability` maintenance token + the
        /// `apple-sample-code` legacy alias on top. `swift-book`
        /// view-source remains opted-out (its pages are co-crawled by
        /// SwiftOrgStrategy via URL-prefix tagging; a separate
        /// `swift-book` leg would double-fetch) — encoded by checking
        /// each provider's `fetchInfo != nil`, since SwiftBookSource
        /// declares `fetchInfo == nil`.
        ///
        /// Static helper because `runAllFetches` is called on `self`
        /// but iterates source-ids without needing instance state.
        private static func allFetchableSources() -> [String] {
            let registry = CLIImpl.makeProductionSourceRegistry()
            var ids = registry.allEnabled
                .filter { $0.fetchInfo != nil }
                .map(\.definition.id)
            // appleSampleCode is the legacy alias for samples; the
            // dispatch in `fetch --source apple-sample-code` canonicalises
            // to `samples`. Listing both here preserves the pre-#1042
            // dual-keyed behaviour for the `--source all` enumerator.
            if !ids.contains(Shared.Constants.SourcePrefix.appleSampleCode) {
                ids.append(Shared.Constants.SourcePrefix.appleSampleCode)
            }
            // `availability` is a non-source maintenance token (refreshes
            // the bundled SDK availability data file). Not registered as
            // a SourceProvider; threaded through the fetch surface as a
            // sibling leg.
            ids.append("availability")
            return ids
        }

        /// Lookup the user-facing display name for a source-id. For
        /// registered providers, reads from the registry's FetchInfo;
        /// for special tokens (`all`, `availability`,
        /// `apple-sample-code`), uses hardcoded labels.
        private static func displayName(forSource source: String) -> String {
            // Special tokens (not in the registry).
            switch source {
            case "all": return Shared.Constants.DisplayName.allDocs
            case "availability": return "API Availability Data"
            case Shared.Constants.SourcePrefix.appleSampleCode:
                return Shared.Constants.DisplayName.sampleCode
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
            case Shared.Constants.SourcePrefix.appleSampleCode:
                // apple-sample-code shares the sample-code directory with
                // the GitHub-based `samples` source (pre-#1031 FetchType
                // .code and .samples both mapped to .sampleCodeDirectory).
                return paths.sampleCodeDirectory.path
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
            // #1042 Cluster 9+13: the key's rawValue IS the dirname.
            // `.baseDirectory` is the only edge case — it points at the
            // base itself, not a sub-directory under it.
            if key == .baseDirectory {
                return paths.baseDirectory
            }
            return paths.directory(named: key.rawValue)
        }

        private mutating func runAllFetches() async throws {
            Cupertino.Context.composition.logging.recording.info("📚 Fetching all documentation types in parallel:\n")
            let baseCommand = self

            try await withThrowingTaskGroup(of: (String, Result<Void, Error>).self) { group in
                for sourceID in Self.allFetchableSources() {
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
        // checkForSession lifted to Ingest.Session.checkForSession (#247)
        // #673 Phase D iter-5: 174-line body — Stage 2 of the
        // packages fetch: priority-catalog load → resolve → per-archive
        // download → magic-bytes validation → on-disk catalog write →
        // skip-statistics accounting. Linear pipeline; helpers would
        // need to pass a 6-tuple of state to be useful.
        // swiftlint:disable:next function_body_length
        private func runAvailabilityFetch() async throws {
            let docsDir = outputDir.map { URL(fileURLWithPath: $0) }
                ?? Shared.Paths.live().docsDirectory

            guard FileManager.default.fileExists(atPath: docsDir.path) else {
                Cupertino.Context.composition.logging.recording.error("❌ Documentation directory not found: \(docsDir.path)")
                Cupertino.Context.composition.logging.recording.info("   Run 'cupertino fetch --source apple-docs' first to download documentation.")
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
    }
}

// FetchURLsError lifted to Ingest.FetchURLsError (#247)
