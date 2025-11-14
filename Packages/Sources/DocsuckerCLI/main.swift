import Foundation
import ArgumentParser
import DocsuckerShared
import DocsuckerCore
import DocsuckerSearch
import DocsuckerLogging

// MARK: - Docsucker CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct AppleDocsucker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appledocsucker",
        abstract: "Apple Documentation Crawler",
        version: "1.0.0",
        subcommands: [Crawl.self, CrawlEvolution.self, DownloadSamples.self, ExportPDF.self, Update.self, BuildIndex.self, Config.self],
        defaultSubcommand: Crawl.self
    )
}

// MARK: - Crawl Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Crawl: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Crawl Apple documentation and save as Markdown"
        )

        @Option(name: .long, help: "Start URL to crawl from")
        var startURL: String = "https://developer.apple.com/documentation/"

        @Option(name: .long, help: "Maximum number of pages to crawl")
        var maxPages: Int = 15000

        @Option(name: .long, help: "Maximum depth to crawl")
        var maxDepth: Int = 15

        @Option(name: .long, help: "Output directory for documentation")
        var outputDir: String = "~/.docsucker/docs"

        @Flag(name: .long, help: "Force recrawl of all pages")
        var force: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("🚀 AppleDocsucker - Apple Documentation Crawler\n")

            // Create configuration
            guard let startURL = URL(string: startURL) else {
                throw ValidationError("Invalid start URL: \(startURL)")
            }

            let config = DocsuckerConfiguration(
                crawler: CrawlerConfiguration(
                    startURL: startURL,
                    maxPages: maxPages,
                    maxDepth: maxDepth,
                    outputDirectory: URL(fileURLWithPath: outputDir).expandingTildeInPath
                ),
                changeDetection: ChangeDetectionConfiguration(
                    forceRecrawl: force
                ),
                output: OutputConfiguration(format: .markdown)
            )

            // Run crawler
            let crawler = await DocumentationCrawler(configuration: config)

            let stats = try await crawler.crawl { progress in
                // Progress callback - use output() for frequent updates (no logging)
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.currentURL.lastPathComponent)")
            }

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
    }
}

// MARK: - Crawl Evolution Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct CrawlEvolution: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "crawl-evolution",
            abstract: "Download Swift Evolution proposals from GitHub"
        )

        @Option(name: .long, help: "Output directory for proposals")
        var outputDir: String = "~/.docsucker/swift-evolution"

        mutating func run() async throws {
            ConsoleLogger.info("🚀 Swift Evolution Crawler\n")

            let outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath

            // Create crawler
            let crawler = await SwiftEvolutionCrawler(outputDirectory: outputURL)

            // Run crawler
            let stats = try await crawler.crawl { progress in
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.proposalID)")
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

// MARK: - Download Samples Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct DownloadSamples: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "download-samples",
            abstract: "Download Apple sample code projects (zip/tar files)"
        )

        @Option(name: .long, help: "Output directory for sample code files")
        var outputDir: String = "~/.docsucker/sample-code"

        @Option(name: .long, help: "Maximum number of samples to download")
        var maxSamples: Int? = nil

        @Flag(name: .long, help: "Force re-download of existing files")
        var force: Bool = false

        @Flag(name: .long, help: "Launch visible browser for authentication (sign in to Apple Developer)")
        var authenticate: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("🚀 Sample Code Downloader\n")

            let outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath

            // Create output directory if needed
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            // Create crawler
            let crawler = await SampleCodeDownloader(
                outputDirectory: outputURL,
                maxSamples: maxSamples,
                forceDownload: force,
                visibleBrowser: authenticate
            )

            // Run crawler
            let stats = try await crawler.download { progress in
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.sampleName)")
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

// MARK: - Export PDF Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct ExportPDF: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export-pdf",
            abstract: "Export markdown documentation to PDF format"
        )

        @Option(name: .long, help: "Input directory containing markdown files")
        var inputDir: String = "~/.docsucker/docs"

        @Option(name: .long, help: "Output directory for PDF files")
        var outputDir: String = "~/.docsucker/pdfs"

        @Option(name: .long, help: "Maximum number of files to convert")
        var maxFiles: Int? = nil

        @Flag(name: .long, help: "Force re-export of existing PDFs")
        var force: Bool = false

        mutating func run() async throws {
            ConsoleLogger.info("📄 PDF Exporter\n")

            let inputURL = URL(fileURLWithPath: inputDir).expandingTildeInPath
            let outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath

            // Create output directory
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

            // Create exporter
            let exporter = await PDFExporter(
                inputDirectory: inputURL,
                outputDirectory: outputURL,
                maxFiles: maxFiles,
                forceExport: force
            )

            // Run export
            let stats = try await exporter.export { progress in
                ConsoleLogger.output("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.fileName)")
            }

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Export completed!")
            ConsoleLogger.info("   Total: \(stats.totalFiles) files")
            ConsoleLogger.info("   Exported: \(stats.exportedFiles)")
            ConsoleLogger.info("   Skipped: \(stats.skippedFiles)")
            ConsoleLogger.info("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                ConsoleLogger.info("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Update Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update existing documentation (incremental crawl)"
        )

        @Option(name: .long, help: "Output directory for documentation")
        var outputDir: String = "~/.docsucker/docs"

        mutating func run() async throws {
            ConsoleLogger.info("🔄 AppleDocsucker - Incremental Update\n")

            // Load configuration
            let configURL = URL(fileURLWithPath: "~/.docsucker/config.json").expandingTildeInPath
            let config: DocsuckerConfiguration

            if FileManager.default.fileExists(atPath: configURL.path) {
                config = try DocsuckerConfiguration.load(from: configURL)
            } else {
                // Use default configuration
                config = DocsuckerConfiguration(
                    crawler: CrawlerConfiguration(
                        outputDirectory: URL(fileURLWithPath: outputDir).expandingTildeInPath
                    )
                )
            }

            // Run crawler
            let crawler = await DocumentationCrawler(configuration: config)
            let stats = try await crawler.crawl()

            ConsoleLogger.output("")
            ConsoleLogger.info("✅ Update completed!")
            ConsoleLogger.info("   Total: \(stats.totalPages) pages")
            ConsoleLogger.info("   New: \(stats.newPages)")
            ConsoleLogger.info("   Updated: \(stats.updatedPages)")
            ConsoleLogger.info("   Skipped: \(stats.skippedPages)")
        }
    }
}

// MARK: - Build Index Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct BuildIndex: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build-index",
            abstract: "Build search index from crawled documentation"
        )

        @Option(name: .long, help: "Directory containing crawled documentation")
        var docsDir: String = "~/.docsucker/docs"

        @Option(name: .long, help: "Directory containing Swift Evolution proposals")
        var evolutionDir: String = "~/.docsucker/swift-evolution"

        @Option(name: .long, help: "Metadata file path")
        var metadataFile: String = "~/.docsucker/metadata.json"

        @Option(name: .long, help: "Search database path")
        var searchDB: String = "~/.docsucker/search.db"

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
                ConsoleLogger.info("   Run 'appledocsucker crawl' first to download documentation.")
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
                ConsoleLogger.info("   Run 'appledocsucker crawl-evolution' to download proposals")
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
            ConsoleLogger.info("\n💡 Tip: Start the MCP server with 'appledocsucker-mcp serve' to enable search")
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

// MARK: - Config Command

extension AppleDocsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage Docsucker configuration",
            subcommands: [Show.self, Init.self]
        )

        @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
        struct Show: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show current configuration"
            )

            func run() async throws {
                let configURL = URL(fileURLWithPath: "~/.docsucker/config.json").expandingTildeInPath

                if FileManager.default.fileExists(atPath: configURL.path) {
                    let config = try DocsuckerConfiguration.load(from: configURL)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(config)
                    if let json = String(data: data, encoding: .utf8) {
                        print(json)
                    }
                } else {
                    ConsoleLogger.info("No configuration file found at: \(configURL.path)")
                    ConsoleLogger.info("Run 'appledocsucker config init' to create one.")
                }
            }
        }

        @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
        struct Init: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Initialize default configuration"
            )

            func run() async throws {
                let configURL = URL(fileURLWithPath: "~/.docsucker/config.json").expandingTildeInPath

                if FileManager.default.fileExists(atPath: configURL.path) {
                    ConsoleLogger.info("⚠️  Configuration file already exists at: \(configURL.path)")
                    ConsoleLogger.info("   Delete it first if you want to recreate.")
                } else {
                    let config = DocsuckerConfiguration()
                    try config.save(to: configURL)
                    ConsoleLogger.info("✅ Configuration created at: \(configURL.path)")
                }
            }
        }
    }
}
