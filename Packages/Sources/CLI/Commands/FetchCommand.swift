import ArgumentParser
import Core
import Foundation
import Logging
import Shared

// MARK: - Fetch Command

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
        package-docs (Swift package READMEs), code (Sample code from Apple), \
        samples (Sample code from GitHub - recommended), \
        archive (Apple Archive guides), all (all types in parallel)
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

    @Flag(name: .long, help: "Force recrawl of all pages")
    var force: Bool = false

    @Flag(name: .long, help: "Resume from saved session (auto-detects and continues)")
    var resume: Bool = false

    @Flag(name: .long, help: "Only download accepted/implemented proposals (evolution type only)")
    var onlyAccepted: Bool = false

    @Option(name: .long, help: "Maximum number of items to fetch (packages/code types only)")
    var limit: Int?

    @Flag(name: .long, help: "Launch visible browser for authentication (code type only)")
    var authenticate: Bool = false

    @Flag(name: .long, help: "Use Apple's JSON API instead of WKWebView (faster, no memory issues)")
    var useJsonApi: Bool = false

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

        // Web crawl types (docs, swift, evolution)
        if type == .evolution {
            try await runEvolutionCrawl()
            return
        }

        try await runStandardCrawl()
    }

    private func logStartMessage() {
        if resume {
            Logging.ConsoleLogger.info("🔄 Cupertino - Resuming from saved session\n")
        } else {
            Logging.ConsoleLogger.info("🚀 Cupertino - Fetching \(type.displayName)\n")
        }
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
        let config = createConfiguration(url: url, outputDirectory: outputDirectory)
        try await executeCrawl(with: config)
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
            if let sessionDir = checkForSession(at: candidate, matching: url) {
                return sessionDir
            }
        }

        return try await scanCupertinoDirectory(for: url)
    }

    private func checkForSession(at directory: URL, matching url: URL) -> URL? {
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
        let outputDir = URL(fileURLWithPath: session.outputDirectory)
        Logging.ConsoleLogger.info(
            "📂 Found existing session, resuming to: \(session.outputDirectory)"
        )
        return outputDir
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
            if let sessionDir = checkForSession(at: dir, matching: url) {
                return sessionDir
            }
        }

        return nil
    }

    private func createConfiguration(
        url: URL,
        outputDirectory: URL
    ) -> Shared.Configuration {
        let prefixes: [String]? = allowedPrefixes?
            .split(separator: ",")
            .map { String($0.trimmingCharacters(in: .whitespaces)) }

        return Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(
                startURL: url,
                allowedPrefixes: prefixes,
                maxPages: maxPages,
                maxDepth: maxDepth,
                outputDirectory: outputDirectory,
                useJSONAPI: useJsonApi
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
            resume: resume
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
            Logging.ConsoleLogger.error("❌ Error: No priority packages found")
            Logging.ConsoleLogger.error("   Searched:")
            Logging.ConsoleLogger.error("   - ~/.cupertino/packages/priority-packages.json")
            Logging.ConsoleLogger.error("   - Shared.Constants.CriticalApplePackages")
            Logging.ConsoleLogger.error("   - Shared.Constants.KnownEcosystemPackages")
            Logging.ConsoleLogger.error("\n   Please ensure at least one package source is configured.")
            throw ExitCode.failure
        }

        // Convert to PackageReference format
        let packageRefs = priorityPackages.compactMap { pkg -> PackageReference? in
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

            let isApple = owner == "apple" || owner == "swiftlang" || owner == "swift-server"
            return PackageReference(
                owner: owner,
                repo: pkg.repo,
                url: pkg.url,
                priority: isApple ? .appleOfficial : .ecosystem
            )
        }

        Logging.ConsoleLogger.info("📦 Downloading documentation for \(packageRefs.count) priority packages...")
        Logging.ConsoleLogger.info("   Output: \(outputURL.path)\n")

        let downloader = Core.PackageDocumentationDownloader(outputDirectory: outputURL)

        let stats = try await downloader.download(packages: packageRefs) { progress in
            let percent = String(format: "%.1f", progress.percentage)
            Logging.ConsoleLogger.output("   Progress: \(percent)% - \(progress.currentPackage)")
        }

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Download completed!")
        Logging.ConsoleLogger.info("   Total packages: \(stats.totalPackages)")
        Logging.ConsoleLogger.info("   New READMEs: \(stats.newREADMEs)")
        Logging.ConsoleLogger.info("   Updated READMEs: \(stats.updatedREADMEs)")
        Logging.ConsoleLogger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            Logging.ConsoleLogger.info("   Duration: \(Int(duration))s")
        }
        Logging.ConsoleLogger.info("\n📁 Output: \(outputURL.path)/")
    }

    private func runCodeFetch() async throws {
        let defaultPath = Shared.Constants.defaultSampleCodeDirectory.path
        let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let crawler = await SampleCodeDownloader(
            outputDirectory: outputURL,
            maxSamples: limit,
            forceDownload: force,
            visibleBrowser: authenticate
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

    private func loadArchiveGuides() async throws -> [ArchiveGuideInfo] {
        // If start URL is provided, use it (no framework info available)
        if let startURL, let url = URL(string: startURL) {
            return [ArchiveGuideInfo(url: url, framework: "")]
        }

        // Otherwise use the curated list of essential archive guides with framework info
        return ArchiveGuideCatalog.essentialGuidesWithInfo
    }
}
