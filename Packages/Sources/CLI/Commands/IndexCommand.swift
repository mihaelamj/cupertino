import ArgumentParser
import Core
import Foundation
import Logging
import SampleIndex
import Shared

// MARK: - Index Command

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct IndexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Index sample code for search",
        discussion: """
        Indexes Apple sample code projects for full-text search.
        Creates a separate database (~/.cupertino/samples.db) optimized for code search.

        IMPORTANT: Run 'cupertino cleanup' before indexing to remove unnecessary files
        from sample code archives. This significantly reduces index size and improves
        search quality.

        Workflow:
        1. cupertino fetch --type code    # Download sample code
        2. cupertino cleanup              # Clean up archives (required)
        3. cupertino index                # Index for search

        The index includes:
        • Project metadata (title, description, frameworks)
        • README content
        • Source files (Swift, Objective-C, Metal, etc.)
        """
    )

    @Option(
        name: .long,
        help: "Sample code directory (default: ~/.cupertino/sample-code)"
    )
    var sampleCodeDir: String?

    @Option(
        name: .long,
        help: "Database path (default: ~/.cupertino/samples.db)"
    )
    var database: String?

    @Flag(
        name: .long,
        help: "Force reindex all projects (even if already indexed)"
    )
    var force: Bool = false

    @Flag(
        name: .long,
        help: "Clear existing index before indexing"
    )
    var clear: Bool = false

    mutating func run() async throws {
        Log.output("📦 Cupertino - Sample Code Indexer")
        Log.output("")

        // Resolve paths
        let sampleCodeURL: URL
        if let customDir = sampleCodeDir {
            sampleCodeURL = URL(fileURLWithPath: customDir).expandingTildeInPath
        } else {
            sampleCodeURL = SampleIndex.defaultSampleCodeDirectory
        }

        let databaseURL: URL
        if let customDB = database {
            databaseURL = URL(fileURLWithPath: customDB).expandingTildeInPath
        } else {
            databaseURL = SampleIndex.defaultDatabasePath
        }

        // Check sample code directory exists
        guard FileManager.default.fileExists(atPath: sampleCodeURL.path) else {
            Log.error("Sample code directory not found: \(sampleCodeURL.path)")
            Log.error("Run 'cupertino fetch --type code' first to download sample code.")
            throw ExitCode.failure
        }

        Log.output("   Sample code: \(sampleCodeURL.path)")
        Log.output("   Database: \(databaseURL.path)")
        Log.output("")

        // If database exists and we have samples, delete it for fresh index
        // This ensures schema updates and clean symbol extraction
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            Log.output("🗑️  Removing existing database for fresh index...")
            try FileManager.default.removeItem(at: databaseURL)
        }

        // Initialize database (creates fresh with latest schema)
        let db = try await SampleIndex.Database(dbPath: databaseURL)

        // Clear if requested (redundant now but kept for explicit --clear flag)
        if clear {
            Log.output("🗑️  Clearing existing index...")
            try await db.clearAll()
        }

        // Get current counts
        let existingProjects = try await db.projectCount()
        let existingFiles = try await db.fileCount()

        if existingProjects > 0, !force, !clear {
            Log.output("ℹ️  Found existing index with \(existingProjects) projects, \(existingFiles) files")
            Log.output("   Use --force to reindex all, or --clear to start fresh")
            Log.output("")
        }

        // Load sample code catalog for metadata
        Log.output("📖 Loading sample code catalog...")
        let catalogEntries = await SampleCodeCatalog.allEntries
        Log.output("   Found \(catalogEntries.count) entries in catalog")

        // Convert to SampleCodeEntryInfo
        let entries = catalogEntries.map { entry in
            SampleIndex.SampleCodeEntryInfo(
                title: entry.title,
                description: entry.description,
                frameworks: [entry.framework], // Single framework per entry
                webURL: entry.webURL,
                zipFilename: entry.zipFilename
            )
        }

        // Create builder and index
        Log.output("")
        Log.output("📇 Indexing sample code...")
        Log.output("")

        let builder = SampleIndex.Builder(
            database: db,
            sampleCodeDirectory: sampleCodeURL
        )

        let startTime = Date()

        // Using a class to hold mutable state since @Sendable closures can't capture mutable vars
        final class ProgressTracker: @unchecked Sendable {
            var lastPercent = 0.0
        }
        let tracker = ProgressTracker()

        let indexed = try await builder.indexAll(
            entries: entries,
            forceReindex: force
        ) { progress in
            let percent = progress.percentComplete
            if percent - tracker.lastPercent >= 5.0 || progress.projectIndex == progress.totalProjects {
                let statusIcon: String
                switch progress.status {
                case .extracting:
                    statusIcon = "📦"
                case .indexingFiles:
                    statusIcon = "📝"
                case .completed:
                    statusIcon = "✅"
                case .failed:
                    statusIcon = "❌"
                }
                Log.output("   [\(String(format: "%3.0f%%", percent))] \(statusIcon) \(progress.currentProject)")
                tracker.lastPercent = percent
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        // Final statistics
        let finalProjects = try await db.projectCount()
        let finalFiles = try await db.fileCount()
        let finalSymbols = try await db.symbolCount()
        let finalImports = try await db.importCount()

        Log.output("")
        Log.output("✅ Indexing complete!")
        Log.output("")
        Log.output("   Projects indexed: \(indexed)")
        Log.output("   Total projects: \(finalProjects)")
        Log.output("   Total files: \(finalFiles)")
        Log.output("   Symbols extracted: \(finalSymbols)")
        Log.output("   Imports captured: \(finalImports)")
        Log.output("   Duration: \(Int(duration))s")
        Log.output("   Database: \(formatFileSize(databaseURL))")
        Log.output("")
        Log.output("💡 Sample code is now searchable via MCP tools:")
        Log.output("   • search_samples - Search projects and code")
        Log.output("   • list_samples - List all indexed projects")
        Log.output("   • read_sample - Read project README")
        Log.output("   • read_sample_file - Read specific source file")
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
