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

    @Option(name: .long, help: "Base directory (auto-fills all directories from standard structure)")
    var baseDir: String?

    @Option(name: .long, help: "Directory containing crawled documentation")
    var docsDir: String?

    @Option(name: .long, help: "Directory containing Swift Evolution proposals")
    var evolutionDir: String?

    @Option(name: .long, help: "Directory containing Swift.org documentation")
    var swiftOrgDir: String?

    @Option(name: .long, help: "Directory containing package READMEs")
    var packagesDir: String?

    @Option(name: .long, help: "Directory containing Apple Archive documentation")
    var archiveDir: String?

    @Option(name: .long, help: "Metadata file path")
    var metadataFile: String?

    @Option(name: .long, help: "Search database path")
    var searchDB: String?

    @Flag(name: .long, help: "Clear existing index before building")
    var clear: Bool = false

    mutating func run() async throws {
        Logging.ConsoleLogger.info("🔨 Building Search Index\n")

        // Determine effective base directory
        let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        // Individual options override the base-derived paths
        let metadataURL = metadataFile.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.FileName.metadata)

        let docsURL = docsDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.docs)

        let evolutionURL = evolutionDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.swiftEvolution)

        let swiftOrgURL = swiftOrgDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.swiftOrg)

        let packagesURL = packagesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)

        let searchDBURL = searchDB.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

        // Load metadata if it exists (optional)
        let metadata: CrawlMetadata?
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            Logging.ConsoleLogger.info("📖 Loading metadata...")
            metadata = try CrawlMetadata.load(from: metadataURL)
            Logging.ConsoleLogger.info("   Found \(metadata!.pages.count) pages in metadata")
        } else {
            Logging.ConsoleLogger.info("ℹ️  No metadata.json found - will scan directory structure")
            Logging.ConsoleLogger.info("   Note: Resume functionality requires metadata.json")
            metadata = nil
        }

        // Delete existing database to avoid FTS5 duplicate rows
        // (FTS5 doesn't support INSERT OR REPLACE properly)
        if FileManager.default.fileExists(atPath: searchDBURL.path) {
            Logging.ConsoleLogger.info("🗑️  Removing existing database for clean re-index...")
            try FileManager.default.removeItem(at: searchDBURL)
        }

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

        // Check if Swift.org directory exists
        let hasSwiftOrg = FileManager.default.fileExists(atPath: swiftOrgURL.path)
        let swiftOrgDirToUse = hasSwiftOrg ? swiftOrgURL : nil

        if !hasSwiftOrg {
            Logging.ConsoleLogger.info("ℹ️  Swift.org directory not found, skipping Swift.org docs")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch --type swift' to download Swift.org documentation")
        }

        // Check if Archive directory exists
        let archiveURL = archiveDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.archive)
        let hasArchive = FileManager.default.fileExists(atPath: archiveURL.path)
        let archiveDirToUse = hasArchive ? archiveURL : nil

        if !hasArchive {
            Logging.ConsoleLogger.info("ℹ️  Archive directory not found, skipping Apple Archive docs")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch --type archive' to download Apple Archive documentation")
        }

        // Build index
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: metadata,
            docsDirectory: docsURL,
            evolutionDirectory: evolutionDirToUse,
            swiftOrgDirectory: swiftOrgDirToUse,
            archiveDirectory: archiveDirToUse
        )

        // Note: Using a class to hold mutable state since @Sendable closures can't capture mutable vars
        // The actor guarantees sequential execution, so this is thread-safe
        final class ProgressTracker: @unchecked Sendable {
            var lastPercent = 0.0
        }
        let tracker = ProgressTracker()

        try await builder.buildIndex(clearExisting: clear) { processed, total in
            let percent = Double(processed) / Double(total) * 100
            if percent - tracker.lastPercent >= 5.0 {
                Logging.ConsoleLogger.output("   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))")
                tracker.lastPercent = percent
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
        Logging.ConsoleLogger.info("\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.commandName) serve' to enable search")
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
