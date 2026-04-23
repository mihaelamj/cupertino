import ArgumentParser
import Foundation
import Logging
import RemoteSync
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

    @Flag(name: .long, help: "Stream documentation from GitHub (instant setup, no local files needed)")
    var remote: Bool = false

    @Flag(name: .long, help: .hidden)
    var packages: Bool = false

    mutating func run() async throws {
        // Hidden: save --packages indexes the downloaded package trees into packages.db.
        if packages {
            try await runPackagesIndexer()
            return
        }

        // Handle remote mode separately
        if remote {
            try await runRemote()
            return
        }

        Logging.ConsoleLogger.info("🔨 Building Search Index\n")

        // Determine effective base directory
        let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        // Individual options override the base-derived paths
        let docsURL = docsDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.docs)

        let evolutionURL = evolutionDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.swiftEvolution)

        let swiftOrgURL = swiftOrgDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.swiftOrg)

        let searchDBURL = searchDB.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

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

        // Check if HIG directory exists
        let higURL = effectiveBase.appendingPathComponent(Shared.Constants.Directory.hig)
        let hasHIG = FileManager.default.fileExists(atPath: higURL.path)
        let higDirToUse = hasHIG ? higURL : nil

        if !hasHIG {
            Logging.ConsoleLogger.info("ℹ️  HIG directory not found, skipping Human Interface Guidelines")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch --type hig' to download HIG documentation")
        }

        // Check if docs have availability data
        let hasAvailability = checkDocsHaveAvailability(docsDir: docsURL)
        if !hasAvailability {
            Logging.ConsoleLogger.info("")
            Logging.ConsoleLogger.info("⚠️  Docs don't have availability data yet")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch --type availability' first for best results")
            Logging.ConsoleLogger.info("   (sample-code and archive derive availability from docs)")
            Logging.ConsoleLogger.info("")
        }

        // Build index (no metadata needed - just scans directories)
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil,
            docsDirectory: docsURL,
            evolutionDirectory: evolutionDirToUse,
            swiftOrgDirectory: swiftOrgDirToUse,
            archiveDirectory: archiveDirToUse,
            higDirectory: higDirToUse
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

    // MARK: - Packages Mode (hidden)

    private func runPackagesIndexer() async throws {
        let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory
        let packagesRoot = packagesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)

        Logging.ConsoleLogger.info("🔨 Indexing packages from \(packagesRoot.path) into \(Shared.Constants.defaultPackagesDatabase.path)")

        // Drop the existing DB so FTS5 doesn't accumulate duplicate rows on
        // re-runs. `PackageIndex.index(...)` deletes-then-inserts per package,
        // but a stale schema from an earlier version of cupertino would confuse
        // things; starting fresh keeps it predictable.
        if clear, FileManager.default.fileExists(atPath: Shared.Constants.defaultPackagesDatabase.path) {
            Logging.ConsoleLogger.info("🗑️  --clear: removing existing packages.db")
            try FileManager.default.removeItem(at: Shared.Constants.defaultPackagesDatabase)
        }

        let index = try await Search.PackageIndex()
        let indexer = Search.PackageIndexer(rootDirectory: packagesRoot, index: index)

        let stats = try await indexer.indexAll { name, done, total in
            if done == 1 || done % 10 == 0 || done == total {
                Logging.ConsoleLogger.output(String(format: "📊 %d/%d — %@", done, total, name as NSString))
            }
        }

        let summary = try await index.summary()
        await index.disconnect()

        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Package indexing completed")
        Logging.ConsoleLogger.info("   Packages indexed this run: \(stats.packagesIndexed)")
        Logging.ConsoleLogger.info("   Packages failed: \(stats.packagesFailed)")
        Logging.ConsoleLogger.info("   Files this run: \(stats.totalFiles)")
        Logging.ConsoleLogger.info("   Bytes this run: \(stats.totalBytes / 1024) KB")
        Logging.ConsoleLogger.info("   Duration: \(Int(stats.durationSeconds))s")
        Logging.ConsoleLogger.info("")
        Logging.ConsoleLogger.info("   Total packages in DB: \(summary.packageCount)")
        Logging.ConsoleLogger.info("   Total files in DB: \(summary.fileCount)")
        Logging.ConsoleLogger.info("   Total bytes in DB: \(summary.bytesIndexed / 1024) KB")
    }

    // MARK: - Remote Mode

    private func runRemote() async throws {
        Logging.ConsoleLogger.info("🚀 Building Search Index from Remote\n")

        // Determine paths
        let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        let searchDBURL = searchDB.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.FileName.searchDatabase)

        let stateFileURL = effectiveBase.appendingPathComponent("remote-save-state.json")

        // Create fetcher and indexer
        let fetcher = GitHubFetcher()
        let indexer = RemoteIndexer(
            fetcher: fetcher,
            stateFileURL: stateFileURL,
            appVersion: Shared.Constants.App.version
        )

        // Check for resumable state
        if await indexer.hasResumableState() {
            let state = await indexer.getState()
            let completedCount = state.frameworksCompleted.count
            let total = state.frameworksTotal
            let framework = state.currentFramework ?? "unknown"

            Logging.ConsoleLogger.info("📋 Found previous session")
            Logging.ConsoleLogger.info("   Phase: \(state.phase.rawValue)")
            Logging.ConsoleLogger.info("   Progress: \(completedCount)/\(total) frameworks")
            if let current = state.currentFramework {
                Logging.ConsoleLogger.info("   Current: \(current) (\(state.currentFileIndex)/\(state.filesTotal) files)")
            }
            Logging.ConsoleLogger.output("")

            // Ask user if they want to resume
            print("Resume from \(framework)? [Y/n] ", terminator: "")
            if let response = readLine()?.lowercased(), response == "n" || response == "no" {
                Logging.ConsoleLogger.info("🔄 Starting fresh...")
                try await indexer.clearState()

                // Delete existing database
                if FileManager.default.fileExists(atPath: searchDBURL.path) {
                    try FileManager.default.removeItem(at: searchDBURL)
                }
            } else {
                Logging.ConsoleLogger.info("▶️  Resuming...")
            }
        } else {
            // Delete existing database for fresh start
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                Logging.ConsoleLogger.info("🗑️  Removing existing database for clean re-index...")
                try FileManager.default.removeItem(at: searchDBURL)
            }
        }

        // Initialize search index
        Logging.ConsoleLogger.info("🗄️  Initializing search database...")
        let searchIndex = try await Search.Index(dbPath: searchDBURL)

        // Create progress display
        let progressDisplay = AnimatedProgress(barWidth: 20, useEmoji: true)
        let reporter = ProgressReporter(display: progressDisplay)

        // Track stats - using a class to hold mutable state for @Sendable closures
        final class StatsTracker: @unchecked Sendable {
            var successCount = 0
            var errorCount = 0
        }
        let stats = StatsTracker()
        let startTime = Date()

        // Run the indexer
        Logging.ConsoleLogger.output("")

        try await indexer.run(
            indexDocument: { uri, source, framework, title, content, jsonData in
                // Index the document
                try await searchIndex.indexDocument(
                    uri: uri,
                    source: source,
                    framework: framework,
                    language: nil,
                    title: title,
                    content: content,
                    filePath: uri,
                    contentHash: content.hashValue.description,
                    lastCrawled: Date(),
                    sourceType: source,
                    packageId: nil,
                    jsonData: jsonData
                )
            },
            onProgress: { progress in
                reporter.update(progress)
            },
            onDocument: { result in
                if result.success {
                    stats.successCount += 1
                } else {
                    stats.errorCount += 1
                }
            }
        )

        // Show final statistics
        let elapsed = Date().timeIntervalSince(startTime)
        let docCount = try await searchIndex.documentCount()
        let frameworks = try await searchIndex.listFrameworks()

        reporter.finish(message: "")
        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Remote sync completed!")
        Logging.ConsoleLogger.info("   Total documents: \(docCount)")
        Logging.ConsoleLogger.info("   Frameworks: \(frameworks.count)")
        Logging.ConsoleLogger.info("   Indexed: \(stats.successCount) | Errors: \(stats.errorCount)")
        Logging.ConsoleLogger.info("   Time: \(Shared.Formatting.formatDuration(elapsed))")
        Logging.ConsoleLogger.info("   Database: \(searchDBURL.path)")
        Logging.ConsoleLogger.info("   Size: \(formatFileSize(searchDBURL))")
        Logging.ConsoleLogger.info("\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.commandName) serve' to enable search")
    }

    /// Check if docs directory has availability data by sampling a few JSON files
    private func checkDocsHaveAvailability(docsDir: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: docsDir.path) else {
            return false
        }

        // Sample a few framework directories
        guard let frameworks = try? FileManager.default.contentsOfDirectory(
            at: docsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        // Check first 3 frameworks for availability
        var checkedCount = 0
        var hasAvailabilityCount = 0

        for frameworkDir in frameworks.prefix(5) {
            guard frameworkDir.hasDirectoryPath else { continue }

            // Find first JSON file in framework
            if let files = try? FileManager.default.contentsOfDirectory(
                at: frameworkDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for file in files where file.pathExtension == "json" {
                    checkedCount += 1

                    // Check if file has availability key
                    if let data = try? Data(contentsOf: file),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["availability"] != nil {
                        hasAvailabilityCount += 1
                    }

                    break // Only check one file per framework
                }
            }

            if checkedCount >= 3 {
                break
            }
        }

        // Consider "has availability" if at least 2 out of 3 sampled files have it
        return checkedCount > 0 && hasAvailabilityCount >= (checkedCount / 2)
    }
}
