import ArgumentParser
import CupertinoCore
import CupertinoLogging
import CupertinoSearch
import CupertinoShared
import Foundation

// MARK: - Crawl Command

extension Cupertino {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Crawl: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Crawl documentation using WKWebView"
        )

        @Option(
            name: .long,
            help: """
            Type of documentation to crawl: docs (Apple), swift (Swift.org), \
            evolution (Swift Evolution), packages (Swift packages)
            """
        )
        var type: CrawlType = .docs

        @Option(name: .long, help: "Start URL to crawl from (overrides --type default)")
        var startURL: String?

        @Option(name: .long, help: "Maximum number of pages to crawl")
        var maxPages: Int = CupertinoConstants.Limit.defaultMaxPages

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

        mutating func validate() throws {
            print("DEBUG: Crawl.validate() called")
        }

        mutating func run() async throws {
            print("DEBUG: Crawl.run() called!")
            do {
                logStartMessage()

                if type == .all {
                    try await runAllCrawls()
                    return
                }

                if type == .evolution {
                    try await runEvolutionCrawl()
                    return
                }

                try await runStandardCrawl()
            } catch {
                print("DEBUG: Error in run(): \(error)")
                throw error
            }
        }

        private func logStartMessage() {
            if resume {
                ConsoleLogger.info("🔄 AppleCupertino - Resuming from saved session\n")
            } else {
                ConsoleLogger.info("🚀 AppleCupertino - Crawling \(type.displayName)\n")
            }
        }

        private mutating func runAllCrawls() async throws {
            ConsoleLogger.info("📚 Crawling all documentation types in parallel:\n")
            let baseCommand = self

            try await withThrowingTaskGroup(of: (CrawlType, Result<Void, Error>).self) { group in
                for crawlType in CrawlType.allTypes {
                    group.addTask {
                        await Self.crawlSingleType(crawlType, baseCommand: baseCommand)
                    }
                }

                let results = try await collectCrawlResults(from: &group)
                try validateCrawlResults(results)
            }
        }

        private static func crawlSingleType(
            _ crawlType: CrawlType,
            baseCommand: Crawl
        ) async -> (CrawlType, Result<Void, Error>) {
            ConsoleLogger.info("🚀 Starting \(crawlType.displayName)...")
            var crawlCommand = baseCommand
            crawlCommand.type = crawlType
            crawlCommand.outputDir = crawlType.defaultOutputDir

            do {
                try await crawlCommand.run()
                return (crawlType, .success(()))
            } catch {
                return (crawlType, .failure(error))
            }
        }

        private func collectCrawlResults(
            from group: inout ThrowingTaskGroup<(CrawlType, Result<Void, Error>), Error>
        ) async throws -> [(CrawlType, Result<Void, Error>)] {
            var results: [(CrawlType, Result<Void, Error>)] = []
            for try await result in group {
                results.append(result)
                let (crawlType, outcome) = result
                switch outcome {
                case .success:
                    ConsoleLogger.info("✅ Completed \(crawlType.displayName)")
                case .failure(let error):
                    ConsoleLogger.error("❌ Failed \(crawlType.displayName): \(error)")
                }
            }
            return results
        }

        private func validateCrawlResults(_ results: [(CrawlType, Result<Void, Error>)]) throws {
            let failures = results.filter {
                if case .failure = $0.1 { return true }
                return false
            }

            if failures.isEmpty {
                ConsoleLogger.info("\n✅ All documentation types crawled successfully!")
            } else {
                ConsoleLogger.info("\n⚠️  Completed with \(failures.count) failure(s)")
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
                CupertinoConstants.defaultDocsDirectory,
                CupertinoConstants.defaultSwiftOrgDirectory,
                CupertinoConstants.defaultSwiftBookDirectory,
            ]

            for candidate in candidates {
                if let sessionDir = checkForSession(at: candidate, matching: url) {
                    return sessionDir
                }
            }

            return try await scanCupertinoDirectory(for: url)
        }

        private func checkForSession(at directory: URL, matching url: URL) -> URL? {
            let metadataFile = directory.appendingPathComponent(CupertinoConstants.FileName.metadata)
            guard FileManager.default.fileExists(atPath: metadataFile.path),
                  let data = try? Data(contentsOf: metadataFile),
                  let metadata = try? JSONDecoder().decode(CrawlMetadata.self, from: data),
                  let session = metadata.crawlState,
                  session.isActive,
                  session.startURL == url.absoluteString,
                  let outputDir = URL(string: session.outputDirectory)
            else {
                return nil
            }
            ConsoleLogger.info(
                "📂 Found existing session, resuming to: \(session.outputDirectory)"
            )
            return outputDir
        }

        private func scanCupertinoDirectory(for url: URL) async throws -> URL? {
            let cupertinoDir = CupertinoConstants.defaultBaseDirectory

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
        ) -> CupertinoConfiguration {
            let prefixes: [String]? = allowedPrefixes?
                .split(separator: ",")
                .map { String($0.trimmingCharacters(in: .whitespaces)) }

            return CupertinoConfiguration(
                crawler: CrawlerConfiguration(
                    startURL: url,
                    allowedPrefixes: prefixes,
                    maxPages: maxPages,
                    maxDepth: maxDepth,
                    outputDirectory: outputDirectory
                ),
                changeDetection: ChangeDetectionConfiguration(
                    forceRecrawl: force,
                    outputDirectory: outputDirectory
                ),
                output: OutputConfiguration(format: .markdown)
            )
        }

        private func executeCrawl(with config: CupertinoConfiguration) async throws {
            let crawler = await DocumentationCrawler(configuration: config)
            let stats = try await crawler.crawl { progress in
                let percentage = String(format: "%.1f", progress.percentage)
                let urlComponent = progress.currentURL.lastPathComponent
                ConsoleLogger.output("   Progress: \(percentage)% - \(urlComponent)")
            }

            logCrawlCompletion(stats)
        }

        private func logCrawlCompletion(_ stats: CrawlStatistics) {
            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Crawl completed!")
            ConsoleLogger.info("   Total: \(stats.totalPages) pages")
            ConsoleLogger.info("   New: \(stats.newPages)")
            ConsoleLogger.info("   Updated: \(stats.updatedPages)")
            ConsoleLogger.info("   Skipped: \(stats.skippedPages)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }

        private func runEvolutionCrawl() async throws {
            let defaultPath = CupertinoConstants.defaultSwiftEvolutionDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

            let crawler = await SwiftEvolutionCrawler(
                outputDirectory: outputURL,
                onlyAccepted: onlyAccepted
            )

            let stats = try await crawler.crawl { progress in
                let percentage = String(format: "%.1f", progress.percentage)
                ConsoleLogger.output("   Progress: \(percentage)% - \(progress.proposalID)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Download completed!")
            ConsoleLogger.info("   Total: \(stats.totalProposals) proposals")
            ConsoleLogger.info("   New: \(stats.newProposals)")
            ConsoleLogger.info("   Updated: \(stats.updatedProposals)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Fetch Command

extension Cupertino {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Fetch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch resources without web crawling"
        )

        @Option(name: .long, help: "Type of resource to fetch: packages (Swift packages), code (Apple sample code)")
        var type: FetchType

        @Option(name: .long, help: "Output directory")
        var outputDir: String?

        @Option(name: .long, help: "Maximum number of items to fetch")
        var limit: Int?

        @Flag(name: .long, help: "Force re-download of existing files")
        var force: Bool = false

        @Flag(name: .long, help: "Resume from checkpoint if interrupted")
        var resume: Bool = false

        @Flag(name: .long, help: "Launch visible browser for authentication (code type only)")
        var authenticate: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("📦 Fetching \(type.displayName)\n")

            switch type {
            case .packages:
                try await runPackageFetch()
            case .code:
                try await runCodeFetch()
            }
        }

        private func runPackageFetch() async throws {
            let defaultPath = CupertinoConstants.defaultPackagesDirectory.path
            let outputURL = URL(fileURLWithPath: outputDir ?? defaultPath).expandingTildeInPath

            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            if ProcessInfo.processInfo.environment[CupertinoConstants.EnvVar.githubToken] == nil {
                ConsoleLogger.info(CupertinoConstants.Message.gitHubTokenTip)
                ConsoleLogger.info("   \(CupertinoConstants.Message.rateLimitWithoutToken)")
                ConsoleLogger.info("   \(CupertinoConstants.Message.rateLimitWithToken)")
                ConsoleLogger.info("   \(CupertinoConstants.Message.exportGitHubToken)\n")
            }

            let fetcher = PackageFetcher(
                outputDirectory: outputURL,
                limit: limit,
                resume: resume
            )

            let stats = try await fetcher.fetch { progress in
                let percent = String(format: "%.1f", progress.percentage)
                ConsoleLogger.output("   Progress: \(percent)% - \(progress.packageName)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Fetch completed!")
            ConsoleLogger.info("   Total packages: \(stats.totalPackages)")
            ConsoleLogger.info("   Successful: \(stats.successfulFetches)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
            ConsoleLogger.info("\n📁 Output: \(outputURL.path)/\(CupertinoConstants.FileName.packagesWithStars)")
        }

        private func runCodeFetch() async throws {
            let defaultPath = CupertinoConstants.defaultSampleCodeDirectory.path
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
                ConsoleLogger.output("   Progress: \(percent)% - \(progress.sampleName)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Download completed!")
            ConsoleLogger.info("   Total: \(stats.totalSamples) samples")
            ConsoleLogger.info("   Downloaded: \(stats.downloadedSamples)")
            ConsoleLogger.info("   Skipped: \(stats.skippedSamples)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Index Command

extension Cupertino {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Index: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build FTS5 search index from crawled documentation"
        )

        @Option(name: .long, help: "Directory containing crawled documentation")
        var docsDir: String = CupertinoConstants.defaultDocsDirectory.path

        @Option(name: .long, help: "Directory containing Swift Evolution proposals")
        var evolutionDir: String = CupertinoConstants.defaultSwiftEvolutionDirectory.path

        @Option(name: .long, help: "Metadata file path")
        var metadataFile: String = CupertinoConstants.defaultMetadataFile.path

        @Option(name: .long, help: "Search database path")
        var searchDB: String = CupertinoConstants.defaultSearchDatabase.path

        @Flag(name: .long, help: "Clear existing index before building")
        var clear: Bool = true

        mutating func run() async throws {
            ConsoleLogger.info("🔨 Building Search Index\n")

            // Expand paths
            let metadataURL = URL(fileURLWithPath: metadataFile).expandingTildeInPath
            let docsURL = URL(fileURLWithPath: docsDir).expandingTildeInPath
            let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
            let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

            // Check if metadata exists
            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                ConsoleLogger.info("❌ Metadata file not found: \(metadataURL.path)")
                ConsoleLogger.info("   Run 'cupertino crawl' first to download documentation.")
                throw ExitCode.failure
            }

            // Load metadata
            ConsoleLogger.info("📖 Loading metadata...")
            let metadata = try CrawlMetadata.load(from: metadataURL)
            ConsoleLogger.info("   Found \(metadata.pages.count) pages in metadata")

            // Initialize search index
            ConsoleLogger.info("🗄️  Initializing search database...")
            let searchIndex = try await SearchIndex(dbPath: searchDBURL)

            // Check if Evolution directory exists
            let hasEvolution = FileManager.default.fileExists(atPath: evolutionURL.path)
            let evolutionDirToUse = hasEvolution ? evolutionURL : nil

            if !hasEvolution {
                ConsoleLogger.info("ℹ️  Swift Evolution directory not found, skipping proposals")
                ConsoleLogger.info("   Run 'cupertino crawl --type evolution' to download proposals")
            }

            // Build index
            let builder = SearchIndexBuilder(
                searchIndex: searchIndex,
                metadata: metadata,
                docsDirectory: docsURL,
                evolutionDirectory: evolutionDirToUse
            )

            var lastPercent = 0.0
            try await builder.buildIndex(clearExisting: clear) { processed, total in
                let percent = Double(processed) / Double(total) * 100
                if percent - lastPercent >= 5.0 {
                    ConsoleLogger.output("   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))")
                    lastPercent = percent
                }
            }

            // Show statistics
            let docCount = try await searchIndex.documentCount()
            let frameworks = try await searchIndex.listFrameworks()

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Search index built successfully!")
            ConsoleLogger.info("   Total documents: \(docCount)")
            ConsoleLogger.info("   Frameworks: \(frameworks.count)")
            ConsoleLogger.info("   Database: \(searchDBURL.path)")
            ConsoleLogger.info("   Size: \(formatFileSize(searchDBURL))")
            ConsoleLogger.info("\n💡 Tip: Start the MCP server with '\(CupertinoConstants.App.mcpCommandName) serve' to enable search")
        }

        private func formatFileSize(_ url: URL) -> String {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int64
            else {
                return "unknown"
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: size)
        }
    }
}
