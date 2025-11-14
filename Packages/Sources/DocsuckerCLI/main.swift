import Foundation
import ArgumentParser
import DocsuckerShared
import DocsuckerCore

// MARK: - Docsucker CLI

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct Docsucker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Apple Documentation Crawler",
        version: "1.0.0",
        subcommands: [Crawl.self, CrawlEvolution.self, Update.self, Config.self],
        defaultSubcommand: Crawl.self
    )
}

// MARK: - Crawl Command

extension Docsucker {
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
            print("🚀 Docsucker - Apple Documentation Crawler\n")

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
                // Progress callback
                print("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.currentURL.lastPathComponent)")
            }

            print("\n✅ Crawl completed!")
            print("   Total: \(stats.totalPages) pages")
            print("   New: \(stats.newPages)")
            print("   Updated: \(stats.updatedPages)")
            print("   Skipped: \(stats.skippedPages)")
            if let duration = stats.duration {
                print("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Crawl Evolution Command

extension Docsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct CrawlEvolution: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "crawl-evolution",
            abstract: "Download Swift Evolution proposals from GitHub"
        )

        @Option(name: .long, help: "Output directory for proposals")
        var outputDir: String = "~/.docsucker/swift-evolution"

        mutating func run() async throws {
            print("🚀 Swift Evolution Crawler\n")

            let outputURL = URL(fileURLWithPath: outputDir).expandingTildeInPath

            // Create crawler
            let crawler = await SwiftEvolutionCrawler(outputDirectory: outputURL)

            // Run crawler
            let stats = try await crawler.crawl { progress in
                print("   Progress: \(String(format: "%.1f", progress.percentage))% - \(progress.proposalID)")
            }

            print("\n✅ Download completed!")
            print("   Total: \(stats.totalProposals) proposals")
            print("   New: \(stats.newProposals)")
            print("   Updated: \(stats.updatedProposals)")
            print("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                print("   Duration: \(Int(duration))s")
            }
        }
    }
}

// MARK: - Update Command

extension Docsucker {
    @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update existing documentation (incremental crawl)"
        )

        @Option(name: .long, help: "Output directory for documentation")
        var outputDir: String = "~/.docsucker/docs"

        mutating func run() async throws {
            print("🔄 Docsucker - Incremental Update\n")

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

            print("\n✅ Update completed!")
            print("   Total: \(stats.totalPages) pages")
            print("   New: \(stats.newPages)")
            print("   Updated: \(stats.updatedPages)")
            print("   Skipped: \(stats.skippedPages)")
        }
    }
}

// MARK: - Config Command

extension Docsucker {
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
                    print("No configuration file found at: \(configURL.path)")
                    print("Run 'docsucker config init' to create one.")
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
                    print("⚠️  Configuration file already exists at: \(configURL.path)")
                    print("   Delete it first if you want to recreate.")
                } else {
                    let config = DocsuckerConfiguration()
                    try config.save(to: configURL)
                    print("✅ Configuration created at: \(configURL.path)")
                }
            }
        }
    }
}
