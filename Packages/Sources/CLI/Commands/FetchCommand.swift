import ArgumentParser
import Availability
import Core
import Foundation
import Logging
import Search
import Shared

/// Lets ArgumentParser parse `--discovery-mode <mode>` directly into the
/// shared enum. The conformance lives here (not in Shared) so the Shared
/// module doesn't take on an ArgumentParser dependency.
extension Shared.DiscoveryMode: ExpressibleByArgument {}

// MARK: - Fetch Command

// swiftlint:disable type_body_length
// Justification: FetchCommand handles 10+ different fetch types (docs, evolution, packages, code, etc.)
// Each type has distinct configuration, progress reporting, and error handling.
// Splitting into separate commands would duplicate shared options and break the unified fetch interface.

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct FetchCommand: AsyncParsableCommand {
    typealias FetchType = Cupertino.FetchType

    static let configuration = CommandConfiguration(
        commandName: "fetch",
        abstract: "Fetch documentation and resources"
    )

    @Option(
        name: .long,
        help: """
        Type of documentation to fetch: docs (Apple), swift (Swift.org), \
        evolution (Swift Evolution), packages (Swift package metadata), \
        code (Sample code from Apple), \
        samples (Sample code from GitHub - recommended), \
        archive (Apple Archive guides), hig (Human Interface Guidelines), \
        availability (API version info for existing docs), \
        all (all types in parallel)
        """
    )
    var type: FetchType = .docs

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
        starting with '#' and blank lines are ignored. (#210)
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
    var discoveryMode: Shared.DiscoveryMode = .auto

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

    mutating func run() async throws {
        logStartMessage()

        if type == .all {
            try await runAllFetches()
            return
        }

        // Direct fetch types (packages, package-docs, code)
        if type == .packages {
            try await runPackageFetch()
            return
        }

        if type == .packageDocs {
            try await runPackageDocsFetch()
            return
        }

        if type == .code {
            try await runCodeFetch()
            return
        }

        if type == .samples {
            try await runSamplesFetch()
            return
        }

        if type == .archive {
            try await runArchiveCrawl()
            return
        }

        if type == .hig {
            try await runHIGCrawl()
            return
        }

        if type == .availability {
            try await runAvailabilityFetch()
            return
        }

        // Web crawl types (docs, swift, evolution)
        if type == .evolution {
            try await runEvolutionCrawl()
            return
        }

        try await runStandardCrawl()
    }

    private func logStartMessage() {
        // The Crawler auto-resumes whenever metadata.json's crawlState is active
        // and matches the start URL — no flag needed. We log "Fetching" here
        // unconditionally; the Crawler itself prints "🔄 Found resumable session"
        // when it actually loads saved state.
        Logging.ConsoleLogger.info("🚀 Cupertino - Fetching \(type.displayName)\n")
    }

    private mutating func runAllFetches() async throws {
        Logging.ConsoleLogger.info("📚 Fetching all documentation types in parallel:\n")
        let baseCommand = self

        try await withThrowingTaskGroup(of: (FetchType, Result<Void, Error>).self) { group in
            for fetchType in FetchType.allTypes {
                group.addTask {
                    await Self.fetchSingleType(fetchType, baseCommand: baseCommand)
                }
            }

            let results = try await collectFetchResults(from: &group)
            try validateFetchResults(results)
        }
    }

    private static func fetchSingleType(
        _ fetchType: FetchType,
        baseCommand: FetchCommand
    ) async -> (FetchType, Result<Void, Error>) {
        Logging.ConsoleLogger.info("🚀 Starting \(fetchType.displayName)...")
        var fetchCommand = baseCommand
        fetchCommand.type = fetchType
        fetchCommand.outputDir = fetchType.defaultOutputDir

        do {
            try await fetchCommand.run()
            return (fetchType, .success(()))
        } catch {
            return (fetchType, .failure(error))
        }
    }

    private func collectFetchResults(
        from group: inout ThrowingTaskGroup<(FetchType, Result<Void, Error>), Error>
    ) async throws -> [(FetchType, Result<Void, Error>)] {
        var results: [(FetchType, Result<Void, Error>)] = []
        for try await result in group {
            results.append(result)
            let (fetchType, outcome) = result
            switch outcome {
            case .success:
                Logging.ConsoleLogger.info("✅ Completed \(fetchType.displayName)")
            case .failure(let error):
                Logging.ConsoleLogger.error("❌ Failed \(fetchType.displayName): \(error)")
            }
        }
        return results
    }

    private func validateFetchResults(_ results: [(FetchType, Result<Void, Error>)]) throws {
        let failures = results.filter {
            if case .failure = $0.1 { return true }
            return false
        }

        if failures.isEmpty {
            Logging.ConsoleLogger.info("\n✅ All documentation types fetched successfully!")
        } else {
            Logging.ConsoleLogger.info("\n⚠️  Completed with \(failures.count) failure(s)")
            throw ExitCode.failure
        }
    }

    private mutating func runStandardCrawl() async throws {
        let url = try validateStartURL()
        let outputDirectory = try await determineOutputDirectory(for: url)
        if startClean {
            try Self.clearSavedSession(at: outputDirectory)
        }
        if retryErrors {
            try Self.requeueErroredURLs(at: outputDirectory, maxDepth: maxDepth)
        }
        if let baselinePath = baseline {
            let baselineURL = URL(fileURLWithPath: baselinePath).expandingTildeInPath
            try Self.requeueFromBaseline(at: outputDirectory, baselineDir: baselineURL, maxDepth: maxDepth)
        }
        if let urlsPath = urls {
            let urlsURL = URL(fileURLWithPath: urlsPath).expandingTildeInPath
            try Self.enqueueURLsFromFile(
                at: outputDirectory,
                urlsFile: urlsURL,
                maxDepth: maxDepth,
                startURL: url
            )
        }
        let config = createConfiguration(url: url, outputDirectory: outputDirectory)
        try await executeCrawl(with: config)
    }

    /// Wipe `crawlState` from `metadata.json` so the Crawler treats this as a
    /// fresh run. Page-level state (frameworks, stats, pages dict) is preserved
    /// — `--force` is what re-fetches existing pages on disk; `--start-clean`
    /// just discards the queue/visited resume marker.
    ///
    /// `internal static` so tests in `CLICommandTests` can exercise it directly
    /// without parsing a full `FetchCommand` from args.
    static func clearSavedSession(at outputDirectory: URL) throws {
        let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            Logging.ConsoleLogger.info("🧹 --start-clean: no saved session to clear at \(outputDirectory.path)")
            return
        }
        var metadata = try CrawlMetadata.load(from: metadataFile)
        metadata.crawlState = nil
        try metadata.save(to: metadataFile)
        Logging.ConsoleLogger.info("🧹 --start-clean: cleared saved session at \(metadataFile.path)")
    }

    /// Re-queue URLs that the crawler visited but never saved to the pages
    /// dict — typically pages whose save failed (filename too long, write
    /// errors, etc.). They get removed from the visited set and appended to
    /// the queue at the configured `maxDepth`, so the resumed crawl retries
    /// them without re-discovering their children (already in the queue).
    ///
    /// `internal static` so tests can exercise it directly.
    static func requeueErroredURLs(at outputDirectory: URL, maxDepth: Int) throws {
        let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            Logging.ConsoleLogger.info("🔁 --retry-errors: no metadata.json at \(outputDirectory.path)")
            return
        }
        var metadata = try CrawlMetadata.load(from: metadataFile)
        guard var crawlState = metadata.crawlState else {
            Logging.ConsoleLogger.info("🔁 --retry-errors: no saved crawlState — nothing to retry")
            return
        }

        let savedURLs = Set(metadata.pages.keys)
        let errored = crawlState.visited.subtracting(savedURLs)
        guard !errored.isEmpty else {
            Logging.ConsoleLogger.info("🔁 --retry-errors: no errored URLs to retry (every visited URL is in the pages dict)")
            return
        }

        // Prepend so retries happen before the existing queue tail —
        // semantically "retry errors first" matches user expectation when
        // running `--retry-errors` after a save-bug fix.
        let erroredItems = errored.map { QueuedURL(url: $0, depth: maxDepth) }
        crawlState.queue = erroredItems + crawlState.queue
        for url in errored {
            crawlState.visited.remove(url)
        }
        crawlState.lastSaveTime = Date()
        metadata.crawlState = crawlState
        try metadata.save(to: metadataFile)

        Logging.ConsoleLogger.info("🔁 --retry-errors: re-queued \(errored.count) errored URL(s) at depth \(maxDepth) (front of queue)")
    }

    /// Inject URLs from a known-good baseline corpus that aren't in the
    /// current crawl's known set (queue ∪ visited ∪ pages keys). Comparison
    /// is case-insensitive on the URL path so the broken-extractor's
    /// case-mixed output still matches the baseline's casing.
    ///
    /// `baselineDir` should point at the `docs/` subtree of a prior corpus
    /// (e.g. `~/Developer/.../cupertino-docs/docs`). Each file's `.url` field
    /// is read; URLs not in the current set are prepended to the queue at
    /// `maxDepth` so the resumed crawl doesn't re-discover their children
    /// (which the baseline already crawled).
    ///
    /// `internal static` so tests can exercise it directly.
    static func requeueFromBaseline(at outputDirectory: URL, baselineDir: URL, maxDepth: Int) throws {
        let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            Logging.ConsoleLogger.info("🩹 --baseline: no metadata.json at \(outputDirectory.path)")
            return
        }
        guard FileManager.default.fileExists(atPath: baselineDir.path) else {
            Logging.ConsoleLogger.info("🩹 --baseline: directory not found at \(baselineDir.path)")
            return
        }

        var metadata = try CrawlMetadata.load(from: metadataFile)
        guard var crawlState = metadata.crawlState else {
            Logging.ConsoleLogger.info("🩹 --baseline: no saved crawlState — run with auto-resume or --start-clean first")
            return
        }

        // Collect baseline URLs by reading each .json file's `url` field.
        let baselineURLs = collectBaselineURLs(in: baselineDir)
        guard !baselineURLs.isEmpty else {
            Logging.ConsoleLogger.info("🩹 --baseline: no URLs found in baseline at \(baselineDir.path)")
            return
        }

        // Build the case-insensitive known-set from queue ∪ visited ∪ pages.
        var knownLowercased = Set<String>()
        knownLowercased.reserveCapacity(crawlState.visited.count + crawlState.queue.count + metadata.pages.count)
        for url in crawlState.visited {
            knownLowercased.insert(lowercaseDocPath(url))
        }
        for queued in crawlState.queue {
            knownLowercased.insert(lowercaseDocPath(queued.url))
        }
        for url in metadata.pages.keys {
            knownLowercased.insert(lowercaseDocPath(url))
        }

        // Find baseline URLs not in the known set (case-insensitive).
        var missing: [String] = []
        var seenLowercased = Set<String>()
        for url in baselineURLs {
            let key = lowercaseDocPath(url)
            if !knownLowercased.contains(key), seenLowercased.insert(key).inserted {
                missing.append(url)
            }
        }
        guard !missing.isEmpty else {
            Logging.ConsoleLogger.info("🩹 --baseline: every baseline URL already known (\(baselineURLs.count) URLs checked)")
            return
        }

        // Prepend at maxDepth — same approach as --retry-errors so children
        // aren't re-discovered (baseline already crawled them).
        let injected = missing.map { QueuedURL(url: $0, depth: maxDepth) }
        crawlState.queue = injected + crawlState.queue
        crawlState.lastSaveTime = Date()
        metadata.crawlState = crawlState
        try metadata.save(to: metadataFile)

        Logging.ConsoleLogger.info(
            "🩹 --baseline: prepended \(missing.count) missing URL(s) "
                + "from \(baselineURLs.count)-URL baseline at depth \(maxDepth)"
        )
    }

    /// Enqueue every URL listed in `urlsFile` (one URL per line) at
    /// depth 0. The crawler then follows each URL's outgoing links up
    /// to `maxDepth`, so the caller can use `--max-depth` to control
    /// how deep the descent tree goes (`--max-depth 0` = no descent,
    /// just fetch the listed URLs themselves). Lines starting with `#`
    /// and blank lines are ignored. Initialises `crawlState` if missing
    /// so the helper works against a fresh corpus too. (#210)
    ///
    /// `internal static` so tests can exercise it directly.
    /// `maxDepth` parameter is retained for symmetry with sibling helpers
    /// even though the URLs are always enqueued at depth 0.
    static func enqueueURLsFromFile(
        at outputDirectory: URL,
        urlsFile: URL,
        maxDepth: Int,
        startURL: URL
    ) throws {
        let lines = try String(contentsOf: urlsFile, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else {
            Logging.ConsoleLogger.info("📥 --urls: file \(urlsFile.path) had no URLs to enqueue")
            return
        }

        // Validate each line is a usable URL with a scheme. URL(string:) is
        // permissive and accepts bare words ("foo bar") as relative URLs;
        // the scheme check rejects those without rejecting common variants
        // we accept (http, https, file, etc.).
        var validURLs: [String] = []
        for raw in lines {
            guard let parsed = URL(string: raw),
                  let scheme = parsed.scheme,
                  !scheme.isEmpty
            else {
                throw FetchURLsError.invalidURL(line: raw)
            }
            validURLs.append(raw)
        }

        let metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var metadata: CrawlMetadata
        if FileManager.default.fileExists(atPath: metadataFile.path) {
            metadata = try CrawlMetadata.load(from: metadataFile)
        } else {
            metadata = CrawlMetadata()
        }

        var crawlState = metadata.crawlState ?? CrawlSessionState(
            startURL: startURL.absoluteString,
            outputDirectory: outputDirectory.path
        )

        // Enqueue at depth 0 so the crawler follows children up to
        // `configuration.maxDepth`. This is the deliberate semantic
        // difference from --retry-errors and --baseline, which queue
        // at maxDepth precisely to suppress descent.
        let newItems = validURLs.map { QueuedURL(url: $0, depth: 0) }
        crawlState.queue = newItems + crawlState.queue
        crawlState.lastSaveTime = Date()
        metadata.crawlState = crawlState
        try metadata.save(to: metadataFile)

        Logging.ConsoleLogger.info(
            "📥 --urls: enqueued \(validURLs.count) URL(s) from \(urlsFile.lastPathComponent) at depth 0 (descent up to maxDepth=\(maxDepth))"
        )
    }

    /// Walk the baseline directory and return every URL recorded in any
    /// JSON page file's top-level `url` field. Skips files that fail to
    /// parse — corrupt baselines shouldn't block a recrawl.
    private static func collectBaselineURLs(in baselineDir: URL) -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: baselineDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "json" else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any],
                  let url = dict["url"] as? String,
                  !url.isEmpty
            else { continue }
            urls.append(url)
        }
        return urls
    }

    /// Lowercase the `/documentation/...` path portion of an Apple docs URL
    /// so case differences (HTML extractor's lowercase vs JSON extractor's
    /// case-preserving output) don't produce false-positive gaps.
    private static func lowercaseDocPath(_ urlString: String) -> String {
        guard let docMarkerRange = urlString.range(of: "/documentation/") else {
            return urlString.lowercased()
        }
        let prefix = urlString[..<docMarkerRange.upperBound]
        let path = urlString[docMarkerRange.upperBound...].lowercased()
        return prefix + path
    }

    private func validateStartURL() throws -> URL {
        let urlString = startURL ?? type.defaultURL
        guard let url = URL(string: urlString) else {
            throw ValidationError("Invalid start URL: \(urlString)")
        }
        return url
    }

    private func determineOutputDirectory(for url: URL) async throws -> URL {
        if let outputDir {
            return URL(fileURLWithPath: outputDir).expandingTildeInPath
        }
        return try await findExistingSession(for: url)
            ?? URL(fileURLWithPath: type.defaultOutputDir).expandingTildeInPath
    }

    private func findExistingSession(for url: URL) async throws -> URL? {
        let candidates = [
            Shared.Constants.defaultDocsDirectory,
            Shared.Constants.defaultSwiftOrgDirectory,
            Shared.Constants.defaultSwiftBookDirectory,
        ]

        for candidate in candidates {
            if let sessionDir = Self.checkForSession(at: candidate, matching: url) {
                return sessionDir
            }
        }

        return try await scanCupertinoDirectory(for: url)
    }

    /// `internal static` so tests can hit this without parsing a full
    /// `FetchCommand` from args. Pure function on its inputs.
    static func checkForSession(at directory: URL, matching url: URL) -> URL? {
        let metadataFile = directory.appendingPathComponent(Shared.Constants.FileName.metadata)
        guard FileManager.default.fileExists(atPath: metadataFile.path),
              let data = try? Data(contentsOf: metadataFile),
              let metadata = try? JSONCoding.decode(CrawlMetadata.self, from: data),
              let session = metadata.crawlState,
              session.isActive,
              session.startURL == url.absoluteString
        else {
            return nil
        }
        // Return the directory where we *found* metadata.json, not the path
        // stored inside it. The saved `session.outputDirectory` is an absolute
        // path captured on the machine that originally ran the crawl — when
        // the directory is rsynced to another host (different home dir, mounted
        // volume, container), that string points at nothing. The directory we
        // just opened a file from is, by definition, the live output dir. The
        // saved path is preserved in the JSON for diagnostic purposes only.
        Logging.ConsoleLogger.info(
            "📂 Found existing session, resuming to: \(directory.path)"
        )
        return directory
    }

    private func scanCupertinoDirectory(for url: URL) async throws -> URL? {
        let cupertinoDir = Shared.Constants.defaultBaseDirectory

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
            if let sessionDir = Self.checkForSession(at: dir, matching: url) {
                return sessionDir
            }
        }

        return nil
    }

    private func createConfiguration(
        url: URL,
        outputDirectory: URL
    ) -> Shared.Configuration {
        // Use user-provided prefixes, or fall back to type defaults
        let prefixes: [String]? = allowedPrefixes?
            .split(separator: ",")
            .map { String($0.trimmingCharacters(in: .whitespaces)) }
            ?? type.defaultAllowedPrefixes

        return Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: url,
                allowedPrefixes: prefixes,
                maxPages: maxPages,
                maxDepth: maxDepth,
                outputDirectory: outputDirectory,
                discoveryMode: discoveryMode
            ),
            changeDetection: Shared.ChangeDetectionConfiguration(
                forceRecrawl: force,
                outputDirectory: outputDirectory
            ),
            output: Shared.OutputConfiguration(format: .markdown)
        )
    }

    private func executeCrawl(with config: Shared.Configuration) async throws {
        let crawler = await Core.Crawler(configuration: config)
        let stats = try await crawler.crawl { progress in
            let percentage = String(format: "%.1f", progress.percentage)
            let urlComponent = progress.currentURL.lastPathComponent
            Logging.ConsoleLogger.output("   Progress: \(percentage)% - \(urlComponent)")
        }

        logCrawlCompletion(stats)
    }

    private func logCrawlCompletion(_ stats: CrawlStatistics) {
        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Crawl completed!")
        Logging.ConsoleLogger.info("   Total: \(stats.totalPages) pages")
        Logging.ConsoleLogger.info("   New: \(stats.newPages)")
        Logging.ConsoleLogger.info("   Updated: \(stats.updatedPages)")
        Logging.ConsoleLogger.info("   Skipped: \(stats.skippedPages)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
    }

    private func runEvolutionCrawl() async throws {
        let defaultPath = Shared.Constants.defaultSwiftEvolutionDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        let crawler = await Core.EvolutionCrawler(
            outputDirectory: outputURL,
            onlyAccepted: onlyAccepted
        )

        let stats = try await crawler.crawl { progress in
            let percentage = String(format: "%.1f", progress.percentage)
            Logging.ConsoleLogger.output("   Progress: \(percentage)% - \(progress.proposalID)")
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Download completed!")
        Logging.ConsoleLogger.info("   Total: \(stats.totalProposals) proposals")
        Logging.ConsoleLogger.info("   New: \(stats.newProposals)")
        Logging.ConsoleLogger.info("   Updated: \(stats.updatedProposals)")
        Logging.ConsoleLogger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
    }

    private func runPackageFetch() async throws {
        let defaultPath = Shared.Constants.defaultPackagesDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        if ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.githubToken] == nil {
            Logging.ConsoleLogger.info(Shared.Constants.Message.gitHubTokenTip)
            Logging.ConsoleLogger.info("   \(Shared.Constants.Message.rateLimitWithoutToken)")
            Logging.ConsoleLogger.info("   \(Shared.Constants.Message.rateLimitWithToken)")
            Logging.ConsoleLogger.info("   \(Shared.Constants.Message.exportGitHubToken)\n")
        }

        let fetcher = Core.PackageFetcher(
            outputDirectory: outputURL,
            limit: limit,
            resume: !startClean
        )

        let stats = try await fetcher.fetch { progress in
            let percent = String(format: "%.1f", progress.percentage)
            Logging.ConsoleLogger.output("   Progress: \(percent)% - \(progress.packageName)")
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Fetch completed!")
        Logging.ConsoleLogger.info("   Total packages: \(stats.totalPackages)")
        Logging.ConsoleLogger.info("   Successful: \(stats.successfulFetches)")
        Logging.ConsoleLogger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
        Logging.ConsoleLogger.info("\n📁 Output: \(outputURL.path)/\(Shared.Constants.FileName.packagesWithStars)")
    }

    private func runPackageDocsFetch() async throws {
        let defaultPath = Shared.Constants.defaultPackagesDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Load priority packages
        let priorityPackages = await PriorityPackagesCatalog.allPackages

        guard !priorityPackages.isEmpty else {
            let priorityPackagesPath = Shared.Constants.defaultPackagesDirectory
                .appendingPathComponent(Shared.Constants.FileName.priorityPackages)
                .path
            Logging.ConsoleLogger.error("❌ Error: No priority packages found")
            Logging.ConsoleLogger.error("   Searched:")
            Logging.ConsoleLogger.error("   - \(priorityPackagesPath)")
            Logging.ConsoleLogger.error("   - Shared.Constants.CriticalApplePackages")
            Logging.ConsoleLogger.error("   - Shared.Constants.KnownEcosystemPackages")
            Logging.ConsoleLogger.error("\n   Please ensure at least one package source is configured.")
            throw ExitCode.failure
        }

        // Convert to PackageReference format
        let seedRefs = priorityPackages.compactMap { pkg -> PackageReference? in
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
            return PackageReference(
                owner: owner,
                repo: pkg.repo,
                url: pkg.url,
                priority: isApple ? .appleOfficial : .ecosystem
            )
        }

        let exclusions = Core.ExclusionList.load()
        let seedChecksum = Core.ResolvedPackagesStore.checksum(seeds: seedRefs, exclusions: exclusions)
        let resolvedStoreURL = Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(Shared.Constants.FileName.resolvedPackages)
        let canonicalCacheURL = Shared.Constants.defaultBaseDirectory
            .appendingPathComponent(".cache")
            .appendingPathComponent(Shared.Constants.FileName.canonicalOwnersCache)

        let resolvedPackages: [Core.ResolvedPackage]
        if recurse {
            if !refresh,
               let cached = Core.ResolvedPackagesStore.load(from: resolvedStoreURL),
               cached.seedChecksum == seedChecksum {
                Logging.ConsoleLogger.info("🔗 Using cached closure from resolved-packages.json (\(cached.packages.count) packages, generated \(cached.generatedAt))")
                resolvedPackages = cached.packages
            } else {
                if refresh {
                    Logging.ConsoleLogger.info("🔗 --refresh: discarding cached closure, re-walking dependency graphs...")
                } else {
                    Logging.ConsoleLogger.info("🔗 Resolving transitive dependencies for \(seedRefs.count) seed packages...")
                }
                if !exclusions.isEmpty {
                    Logging.ConsoleLogger.info("   Exclusion list in effect: \(exclusions.count) entries")
                }
                let canonicalizer = Core.GitHubCanonicalizer(cacheURL: canonicalCacheURL)
                let manifestCache = Core.ManifestCache(
                    rootDirectory: Shared.Constants.defaultBaseDirectory
                        .appendingPathComponent(".cache")
                        .appendingPathComponent("manifests")
                )
                let resolver = Core.PackageDependencyResolver(
                    canonicalizer: canonicalizer,
                    exclusions: exclusions,
                    manifestCache: manifestCache
                )
                let (resolved, resolverStats) = await resolver.resolve(seeds: seedRefs) { name, done, total in
                    if done == 1 || done % 10 == 0 || done == total {
                        Logging.ConsoleLogger.output("   Resolving: \(done)/\(total) (\(name))")
                    }
                }
                resolvedPackages = resolved
                Logging.ConsoleLogger.info("   Seeds: \(resolverStats.seedCount)")
                Logging.ConsoleLogger.info("   Discovered via dependencies: \(resolverStats.discoveredCount)")
                Logging.ConsoleLogger.info("   Excluded: \(resolverStats.excludedCount)")
                Logging.ConsoleLogger.info("   Skipped (non-GitHub): \(resolverStats.skippedNonGitHub)")
                Logging.ConsoleLogger.info("   Skipped (SPM registry id): \(resolverStats.skippedRegistry)")
                Logging.ConsoleLogger.info("   Missing manifest: \(resolverStats.missingManifest)")
                Logging.ConsoleLogger.info("   Malformed manifest: \(resolverStats.malformedManifest)")
                Logging.ConsoleLogger.info("   Resolver duration: \(Int(resolverStats.duration))s")

                let store = Core.ResolvedPackagesStore(
                    cupertinoVersion: Shared.Constants.App.version,
                    seedChecksum: seedChecksum,
                    packages: resolved
                )
                do {
                    try store.write(to: resolvedStoreURL)
                    Logging.ConsoleLogger.info("   Saved closure to \(resolvedStoreURL.path)")
                } catch {
                    Logging.ConsoleLogger.error("   ⚠️  Could not persist resolved-packages.json: \(error)")
                }
            }
        } else {
            resolvedPackages = seedRefs.map { ref in
                Core.ResolvedPackage(
                    owner: ref.owner,
                    repo: ref.repo,
                    url: ref.url,
                    priority: ref.priority,
                    parents: ["\(ref.owner.lowercased())/\(ref.repo.lowercased())"]
                )
            }
            Logging.ConsoleLogger.info("🔗 Skipping dependency resolution (--no-recurse)")
            if !exclusions.isEmpty {
                Logging.ConsoleLogger.info("   Exclusion list ignored while --no-recurse is set")
            }
        }

        Logging.ConsoleLogger.info("📦 Fetching \(resolvedPackages.count) archives into \(outputURL.path)...")

        let extractor = Core.PackageArchiveExtractor()
        let startedAt = Date()
        var stats = PackageDownloadStatistics(
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
                Logging.ConsoleLogger.info("  ✅ \(label) — \(extraction.files.count) files, \(kb) KB")
            } catch Core.PackageArchiveExtractor.ExtractError.tarballNotFound {
                stats.errors += 1
                Logging.ConsoleLogger.error("  ✗ \(label) — archive not found on any ref")
            } catch Core.PackageArchiveExtractor.ExtractError.tarballTooLarge(let bytes) {
                stats.errors += 1
                Logging.ConsoleLogger.error("  ✗ \(label) — archive too large (\(bytes / 1024 / 1024) MB)")
            } catch {
                stats.errors += 1
                Logging.ConsoleLogger.error("  ✗ \(label) — \(error.localizedDescription)")
            }

            if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 || idx + 1 == resolvedPackages.count {
                let percent = Double(idx + 1) / Double(resolvedPackages.count) * 100
                Logging.ConsoleLogger.output(
                    String(format: "📊 Progress: %.1f%% (%d/%d)", percent, idx + 1, resolvedPackages.count)
                )
            }
        }
        stats.endTime = Date()

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Fetch completed!")
        Logging.ConsoleLogger.info("   New packages: \(stats.newPackages)")
        Logging.ConsoleLogger.info("   Files saved: \(stats.totalFilesSaved)")
        Logging.ConsoleLogger.info("   Bytes saved: \(stats.totalBytesSaved / 1024) KB")
        Logging.ConsoleLogger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
        Logging.ConsoleLogger.info("\n📁 Packages: \(outputURL.path)")
        Logging.ConsoleLogger.info("   Next: index them into \(Shared.Constants.defaultPackagesDatabase.path) via `save --type packages`")
    }

    private func writePackageManifest(
        resolved: Core.ResolvedPackage,
        extraction: Core.PackageArchiveExtractor.Result,
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

    private func runCodeFetch() async throws {
        let defaultPath = Shared.Constants.defaultSampleCodeDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let crawler = await SampleCodeDownloader(
            outputDirectory: outputURL,
            maxSamples: limit,
            forceDownload: force
        )

        let stats = try await crawler.download { progress in
            let percent = String(format: "%.1f", progress.percentage)
            Logging.ConsoleLogger.output("   Progress: \(percent)% - \(progress.sampleName)")
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Download completed!")
        Logging.ConsoleLogger.info("   Total: \(stats.totalSamples) samples")
        Logging.ConsoleLogger.info("   Downloaded: \(stats.downloadedSamples)")
        Logging.ConsoleLogger.info("   Skipped: \(stats.skippedSamples)")
        Logging.ConsoleLogger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
    }

    private func runSamplesFetch() async throws {
        let defaultPath = Shared.Constants.defaultSampleCodeDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        let fetcher = GitHubSampleCodeFetcher(outputDirectory: outputURL)

        let stats = try await fetcher.fetch { progress in
            Logging.ConsoleLogger.output("   \(progress.message)")
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Fetch completed!")
        Logging.ConsoleLogger.info("   Action: \(stats.action.description)")
        Logging.ConsoleLogger.info("   Projects: \(stats.projectCount)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
        Logging.ConsoleLogger.info("\n📁 Output: \(outputURL.path)/cupertino-sample-code")
    }

    private func runArchiveCrawl() async throws {
        let defaultPath = Shared.Constants.defaultArchiveDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Load guides from bundled manifest or command line
        let guides = try await loadArchiveGuides()

        guard !guides.isEmpty else {
            Logging.ConsoleLogger.error("❌ No archive guides configured")
            Logging.ConsoleLogger.info("   Use --start-url to specify guide URLs or configure the manifest")
            throw ExitCode.failure
        }

        Logging.ConsoleLogger.info("📚 Crawling \(guides.count) Apple Archive guides...")
        Logging.ConsoleLogger.info("   Output: \(outputURL.path)\n")

        let crawler = await Core.AppleArchiveCrawler(
            outputDirectory: outputURL,
            guides: guides,
            forceRecrawl: force
        )

        let stats = try await crawler.crawl { progress in
            let percent = String(format: "%.1f", progress.percentage)
            Logging.ConsoleLogger.output("   Progress: \(percent)% - \(progress.currentItem)")
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Crawl completed!")
        Logging.ConsoleLogger.info("   Total guides: \(stats.totalGuides)")
        Logging.ConsoleLogger.info("   Total pages: \(stats.totalPages)")
        Logging.ConsoleLogger.info("   New: \(stats.newPages)")
        Logging.ConsoleLogger.info("   Updated: \(stats.updatedPages)")
        Logging.ConsoleLogger.info("   Skipped: \(stats.skippedPages)")
        Logging.ConsoleLogger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
        Logging.ConsoleLogger.info("\n📁 Output: \(outputURL.path)/")
    }

    private func runHIGCrawl() async throws {
        let defaultPath = Shared.Constants.defaultHIGDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        Logging.ConsoleLogger.info("📖 Crawling Human Interface Guidelines...")
        Logging.ConsoleLogger.info("   Output: \(outputURL.path)\n")

        let crawler = await Core.HIGCrawler(
            outputDirectory: outputURL,
            forceRecrawl: force
        )

        let stats = try await crawler.crawl { progress in
            let percent = String(format: "%.1f", progress.percentage)
            Logging.ConsoleLogger.output("   Progress: \(percent)% - \(progress.currentItem)")
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Crawl completed!")
        Logging.ConsoleLogger.info("   Total pages: \(stats.totalPages)")
        Logging.ConsoleLogger.info("   New: \(stats.newPages)")
        Logging.ConsoleLogger.info("   Updated: \(stats.updatedPages)")
        Logging.ConsoleLogger.info("   Skipped: \(stats.skippedPages)")
        Logging.ConsoleLogger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
        Logging.ConsoleLogger.info("\n📁 Output: \(outputURL.path)/")
    }

    private func loadArchiveGuides() async throws -> [ArchiveGuideInfo] {
        // If start URL is provided, use it (no framework info available)
        if let startURL, let url = URL(string: startURL) {
            return [ArchiveGuideInfo(url: url, framework: "")]
        }

        // Otherwise use the curated list of essential archive guides with framework info
        return ArchiveGuideCatalog.essentialGuidesWithInfo
    }

    private func runAvailabilityFetch() async throws {
        let docsDir = outputDir.map { URL(fileURLWithPath: $0) }
            ?? Shared.Constants.defaultDocsDirectory

        guard FileManager.default.fileExists(atPath: docsDir.path) else {
            Logging.ConsoleLogger.error("❌ Documentation directory not found: \(docsDir.path)")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch --type docs' first to download documentation.")
            throw ExitCode.failure
        }

        Logging.ConsoleLogger.info("📊 Fetching API availability data...")
        Logging.ConsoleLogger.info("   Source: \(docsDir.path)")
        Logging.ConsoleLogger.info("   API: developer.apple.com/tutorials/data/documentation\n")

        let configuration: AvailabilityFetcher.Configuration
        if fast {
            configuration = .fast
        } else {
            configuration = AvailabilityFetcher.Configuration(
                concurrency: 50,
                timeout: 1.0,
                skipExisting: !force
            )
        }

        let fetcher = AvailabilityFetcher(
            docsDirectory: docsDir,
            configuration: configuration
        )

        let stats = try await fetcher.fetch { progress in
            let percent = String(format: "%.1f", progress.percentage)
            let successRate = progress.completed > 0
                ? String(format: "%.0f", Double(progress.successful) / Double(progress.completed) * 100)
                : "0"
            Logging.ConsoleLogger.output(
                "   Progress: \(percent)% [\(progress.currentFramework)] \(successRate)% success"
            )
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Availability fetch completed!")
        Logging.ConsoleLogger.info("   Documents scanned: \(stats.totalDocuments)")
        Logging.ConsoleLogger.info("   Updated: \(stats.updatedDocuments)")
        Logging.ConsoleLogger.info("   Skipped: \(stats.skippedDocuments)")
        Logging.ConsoleLogger.info("   Failed: \(stats.failedFetches)")
        Logging.ConsoleLogger.info("   Frameworks: \(stats.frameworksProcessed)")
        Logging.ConsoleLogger.info("   Success rate: \(String(format: "%.1f", stats.successRate))%")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
    }
}

// MARK: - --urls errors (#210)

enum FetchURLsError: Error, LocalizedError {
    case invalidURL(line: String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(line):
            return "--urls: cannot parse URL from line: \(line)"
        }
    }
}
