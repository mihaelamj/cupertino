import ArgumentParser
import Foundation
import Logging
import Search
import Shared

// MARK: - Save Command

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct SaveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "save",
        abstract: "Save documentation to database and build search indexes"
    )

    @Option(name: .long, help: "Directory containing crawled documentation")
    var docsDir: String = Shared.Constants.defaultDocsDirectory.path

    @Option(name: .long, help: "Directory containing Swift Evolution proposals")
    var evolutionDir: String = Shared.Constants.defaultSwiftEvolutionDirectory.path

    @Option(name: .long, help: "Metadata file path")
    var metadataFile: String = Shared.Constants.defaultMetadataFile.path

    @Option(name: .long, help: "Search database path")
    var searchDB: String = Shared.Constants.defaultSearchDatabase.path

    @Flag(name: .long, help: "Clear existing index before building")
    var clear: Bool = false

    mutating func run() async throws {
        Logging.ConsoleLogger.info("🔨 Building Search Index\n")

        // Expand paths
        let metadataURL = URL(fileURLWithPath: metadataFile).expandingTildeInPath
        let docsURL = URL(fileURLWithPath: docsDir).expandingTildeInPath
        let evolutionURL = URL(fileURLWithPath: evolutionDir).expandingTildeInPath
        let searchDBURL = URL(fileURLWithPath: searchDB).expandingTildeInPath

        // Check if metadata exists
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            Logging.ConsoleLogger.info("❌ Metadata file not found: \(metadataURL.path)")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch' first to download documentation.")
            throw ExitCode.failure
        }

        // Load metadata
        Logging.ConsoleLogger.info("📖 Loading metadata...")
        let metadata = try CrawlMetadata.load(from: metadataURL)
        Logging.ConsoleLogger.info("   Found \(metadata.pages.count) pages in metadata")

        // Initialize search index
        Logging.ConsoleLogger.info("🗄️  Initializing search database...")
        let searchIndex = try await Search.Index(dbPath: searchDBURL)

        // Check if Evolution directory exists
        let hasEvolution = FileManager.default.fileExists(atPath: evolutionURL.path)
        let evolutionDirToUse = hasEvolution ? evolutionURL : nil

        if !hasEvolution {
            Logging.ConsoleLogger.info("ℹ️  Swift Evolution directory not found, skipping proposals")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch --type evolution' to download proposals")
        }

        // Build index
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: metadata,
            docsDirectory: docsURL,
            evolutionDirectory: evolutionDirToUse
        )

        var lastPercent = 0.0
        try await builder.buildIndex(clearExisting: clear) { processed, total in
            let percent = Double(processed) / Double(total) * 100
            if percent - lastPercent >= 5.0 {
                Logging.ConsoleLogger.output("   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))")
                lastPercent = percent
            }
        }

        // Show statistics
        let docCount = try await searchIndex.documentCount()
        let frameworks = try await searchIndex.listFrameworks()

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Search index built successfully!")
        Logging.ConsoleLogger.info("   Total documents: \(docCount)")
        Logging.ConsoleLogger.info("   Frameworks: \(frameworks.count)")
        Logging.ConsoleLogger.info("   Database: \(searchDBURL.path)")
        Logging.ConsoleLogger.info("   Size: \(formatFileSize(searchDBURL))")
        Logging.ConsoleLogger.info("\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.mcpCommandName) serve' to enable search")
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
