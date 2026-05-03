import ArgumentParser
import Core
import Foundation
import Logging
import RemoteSync
import SampleIndex
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

    @Flag(
        name: .long,
        help: """
        Build search.db (Apple docs + Swift Evolution + HIG + Archive + \
        Swift.org + Swift Book). Defaults to ON when no scope flag is \
        passed. (#231)
        """
    )
    var docs: Bool = false

    @Flag(
        name: .long,
        help: """
        Build packages.db from extracted package archives at \
        `~/.cupertino/packages/<owner>/<repo>/`. (#231)
        """
    )
    var packages: Bool = false

    @Flag(
        name: .long,
        help: """
        Build samples.db from extracted sample-code zips at \
        `~/.cupertino/sample-code/`. Replaces the removed `cupertino \
        index` command. (#231)
        """
    )
    var samples: Bool = false

    @Option(
        name: .long,
        help: "Sample-code directory for `--samples` (#231)."
    )
    var samplesDir: String?

    @Option(
        name: .long,
        help: "samples.db path override for `--samples` (#231)."
    )
    var samplesDB: String?

    @Flag(
        name: .long,
        help: "Force re-index of every sample under `--samples` (existing rows wiped)."
    )
    var force: Bool = false

    @Flag(
        name: [.short, .long],
        help: "Skip the preflight summary + confirmation prompt (#232). Auto-skipped when stdin isn't a TTY."
    )
    var yes: Bool = false

    mutating func run() async throws {
        // Handle remote mode separately — it's an entirely different
        // pipeline (streams docs from GitHub) and shouldn't combine with
        // the build-locally scope flags.
        if remote {
            try await runRemote()
            return
        }

        // #231: scope flags. None set → build all three in order
        // (docs → packages → samples). Any combination of the three
        // builds only the requested subset, in the same fixed order.
        let scopeFlagsSet = docs || packages || samples
        let buildDocs = !scopeFlagsSet || docs
        let buildPackages = !scopeFlagsSet || packages
        let buildSamples = !scopeFlagsSet || samples

        // #232: preflight summary + confirmation prompt. Surfaces missing
        // sources and un-annotated corpora so the user can bail out before
        // a half-populated save run.
        if !runPreflightAndConfirm(
            buildDocs: buildDocs,
            buildPackages: buildPackages,
            buildSamples: buildSamples
        ) {
            Logging.ConsoleLogger.info("Aborted by user.")
            return
        }

        if buildDocs {
            try await runDocsIndexer()
        }
        if buildPackages {
            try await runPackagesIndexerSafely()
        }
        if buildSamples {
            try await runSamplesIndexerSafely()
        }
    }

    /// Build packages.db; skip with an info log if the source dir is
    /// missing rather than failing the whole `save` invocation. Single-
    /// scope `--packages` callers still see the missing-dir as a hard
    /// error via `runPackagesIndexer` directly.
    private func runPackagesIndexerSafely() async throws {
        let packagesDir = Shared.Constants.defaultPackagesDirectory
        guard FileManager.default.fileExists(atPath: packagesDir.path) else {
            Logging.ConsoleLogger.info(
                "ℹ️  packages directory not found at \(packagesDir.path) — skipping packages step. "
                    + "Run `cupertino fetch --type packages` first."
            )
            return
        }
        try await runPackagesIndexer()
    }

    /// Build samples.db; skip with an info log if the source dir is
    /// missing rather than failing the whole `save` invocation.
    private func runSamplesIndexerSafely() async throws {
        let samplesDirURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? SampleIndex.defaultSampleCodeDirectory
        guard FileManager.default.fileExists(atPath: samplesDirURL.path) else {
            Logging.ConsoleLogger.info(
                "ℹ️  sample-code directory not found at \(samplesDirURL.path) — skipping samples step. "
                    + "Run `cupertino fetch --type samples` first."
            )
            return
        }
        try await runSamplesIndexer()
    }

    /// Body of the legacy `save` (docs-only) path. Renamed so the
    /// scope-flag dispatcher can call it explicitly. #231
    private mutating func runDocsIndexer() async throws {
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
        let hasAvailability = Self.checkDocsHaveAvailability(docsDir: docsURL)
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

    // MARK: - Samples mode (#231: replaces `cupertino index`)

    /// Build samples.db from extracted sample-code zips. Body lifted from
    /// the deleted `IndexCommand.swift`. Same defaults: source dir
    /// `~/.cupertino/sample-code/`, DB at `samples.db` next to base.
    /// `--samples-dir` and `--samples-db` override.
    private func runSamplesIndexer() async throws {
        Log.output("📦 Cupertino - Sample Code Indexer")
        Log.output("")

        let sampleCodeURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? SampleIndex.defaultSampleCodeDirectory

        let databaseURL = samplesDB.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? SampleIndex.defaultDatabasePath

        guard FileManager.default.fileExists(atPath: sampleCodeURL.path) else {
            Log.error("Sample code directory not found: \(sampleCodeURL.path)")
            Log.error("Run 'cupertino fetch --type samples' first to download sample code.")
            throw ExitCode.failure
        }

        Log.output("   Sample code: \(sampleCodeURL.path)")
        Log.output("   Database: \(databaseURL.path)")
        Log.output("")

        // Drop the existing DB for a clean re-index. Matches the
        // search.db / packages.db pattern — FTS5 doesn't tolerate
        // duplicate-row inserts cleanly, so a wipe + rebuild is the
        // simplest correctness story.
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            Log.output("🗑️  Removing existing database for fresh index...")
            try FileManager.default.removeItem(at: databaseURL)
        }

        let database = try await SampleIndex.Database(dbPath: databaseURL)

        if clear {
            Log.output("🗑️  Clearing existing index...")
            try await database.clearAll()
        }

        let existingProjects = try await database.projectCount()
        let existingFiles = try await database.fileCount()
        if existingProjects > 0, !force, !clear {
            Log.output("ℹ️  Found existing index with \(existingProjects) projects, \(existingFiles) files")
            Log.output("   Use --force to reindex all, or --clear to start fresh")
            Log.output("")
        }

        Log.output("📖 Loading sample code catalog...")
        let catalogEntries = await SampleCodeCatalog.allEntries
        Log.output("   Found \(catalogEntries.count) entries in catalog")

        let entries = catalogEntries.map { entry in
            SampleIndex.SampleCodeEntryInfo(
                title: entry.title,
                description: entry.description,
                frameworks: [entry.framework],
                webURL: entry.webURL,
                zipFilename: entry.zipFilename
            )
        }

        Log.output("")
        Log.output("📇 Indexing sample code...")
        Log.output("")

        let builder = SampleIndex.Builder(
            database: database,
            sampleCodeDirectory: sampleCodeURL
        )

        let startTime = Date()

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
                case .extracting: statusIcon = "📦"
                case .indexingFiles: statusIcon = "📝"
                case .completed: statusIcon = "✅"
                case .failed: statusIcon = "❌"
                }
                Log.output("   [\(String(format: "%3.0f%%", percent))] \(statusIcon) \(progress.currentProject)")
                tracker.lastPercent = percent
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        let finalProjects = try await database.projectCount()
        let finalFiles = try await database.fileCount()
        let finalSymbols = try await database.symbolCount()
        let finalImports = try await database.importCount()

        Log.output("")
        Log.output("✅ Indexing complete!")
        Log.output("")
        Log.output("   Projects indexed: \(indexed)")
        Log.output("   Total projects: \(finalProjects)")
        Log.output("   Total files: \(finalFiles)")
        Log.output("   Symbols extracted: \(finalSymbols)")
        Log.output("   Imports captured: \(finalImports)")
        Log.output("   Duration: \(Int(duration))s")
        Log.output("   Database: \(formatSamplesFileSize(databaseURL))")
    }

    private func formatSamplesFileSize(_ url: URL) -> String {
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

    // MARK: - Packages Mode

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

    /// Heuristic: does the docs corpus on disk carry availability
    /// annotations from `cupertino fetch --type availability`? Sampled —
    /// we don't read every page. Good enough for preflight + the inline
    /// docs-mode warning. True when at least half of the sampled JSONs
    /// carry an `availability` key.
    ///
    /// Sampling shape: walk up to `maxFrameworks` framework dirs, look
    /// at the first `.json` in each, peek at the top-level keys.
    /// Tunables live as constants so tests can pin behaviour.
    static func checkDocsHaveAvailability(docsDir: URL) -> Bool {
        let report = sampleDocsAvailability(docsDir: docsDir)
        return report.checked > 0 && report.withAvailability >= (report.checked / 2)
    }

    /// Pure inspection — counts how many sampled docs JSON files carry
    /// an `availability` field. `internal` so tests can pin both the
    /// sampling shape and the threshold logic separately.
    static func sampleDocsAvailability(
        docsDir: URL,
        maxFrameworks: Int = 5,
        maxSamples: Int = 3
    ) -> (checked: Int, withAvailability: Int) {
        guard FileManager.default.fileExists(atPath: docsDir.path) else {
            return (0, 0)
        }
        guard let frameworks = try? FileManager.default.contentsOfDirectory(
            at: docsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var checked = 0
        var withAvailability = 0
        for frameworkDir in frameworks.prefix(maxFrameworks) {
            guard checked < maxSamples else { break }
            guard isDirectory(frameworkDir) else { continue }
            guard let firstJSON = firstJSONFile(in: frameworkDir) else { continue }
            checked += 1
            if jsonContainsAvailability(at: firstJSON) {
                withAvailability += 1
            }
        }
        return (checked, withAvailability)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func firstJSONFile(in directory: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return files.first { $0.pathExtension == "json" }
    }

    private static func jsonContainsAvailability(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["availability"] != nil
    }

    // MARK: - Preflight (#232)

    /// Inspect the on-disk corpus state for the chosen scope and surface
    /// missing or un-annotated sources before any DB write. Returns
    /// `false` when the user opts to abort. Auto-confirms (returns
    /// `true` without prompting) when stdin isn't a TTY or `--yes` was
    /// passed.
    private func runPreflightAndConfirm(
        buildDocs: Bool,
        buildPackages: Bool,
        buildSamples: Bool
    ) -> Bool {
        let lines = Self.preflightLines(
            buildDocs: buildDocs,
            buildPackages: buildPackages,
            buildSamples: buildSamples,
            baseDir: baseDir,
            docsDir: docsDir,
            samplesDir: samplesDir
        )
        Logging.ConsoleLogger.info("🔍 Preflight check for `cupertino save`\n")
        for line in lines {
            Logging.ConsoleLogger.info(line)
        }
        Logging.ConsoleLogger.info("")

        if yes {
            Logging.ConsoleLogger.info("--yes: skipping confirmation, continuing.\n")
            return true
        }
        guard isatty(fileno(stdin)) != 0 else {
            // Not a TTY (piped, scripted, CI) — proceed without prompting
            // so automation doesn't hang.
            return true
        }

        Logging.ConsoleLogger.info("Continue? [Y/n] ")
        guard let response = readLine() else { return true }
        let normalized = response.trimmingCharacters(in: .whitespaces).lowercased()
        return normalized.isEmpty || normalized == "y" || normalized == "yes"
    }

    /// Pure inspection helper — assembled into the printable preflight
    /// summary by `runPreflightAndConfirm`. Lifted out so tests and
    /// `cupertino doctor --save` (#232) can reuse without driving
    /// stdin/stdout. Takes the same path overrides as the SaveCommand
    /// flags so the helper produces the same numbers a real save would.
    static func preflightLines(
        buildDocs: Bool,
        buildPackages: Bool,
        buildSamples: Bool,
        baseDir: String? = nil,
        docsDir: String? = nil,
        samplesDir: String? = nil
    ) -> [String] {
        var lines: [String] = []
        let fm = FileManager.default
        let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        if buildDocs {
            lines.append("  Docs (search.db)")
            let docsURL = docsDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.docs)
            if fm.fileExists(atPath: docsURL.path) {
                let count = (try? fm.subpathsOfDirectory(atPath: docsURL.path).count) ?? 0
                lines.append("    ✓  \(docsURL.path)  (\(count) entries)")
                if Self.checkDocsHaveAvailability(docsDir: docsURL) {
                    lines.append("    ✓  Availability annotation present")
                } else {
                    lines.append("    ⚠  Availability annotation NOT detected")
                    lines.append("       min_ios / min_macos / etc. columns will be NULL.")
                    lines.append("       Run `cupertino fetch --type availability` first for platform filtering.")
                }
            } else {
                lines.append("    ✗  \(docsURL.path)  (missing — docs scope will be skipped)")
            }
            lines.append("")
        }

        if buildPackages {
            lines.append("  Packages (packages.db)")
            let packagesURL = effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)
            if fm.fileExists(atPath: packagesURL.path) {
                let stats = Self.countPackagesAndSidecars(at: packagesURL)
                lines.append("    ✓  \(packagesURL.path)  (\(stats.packages) packages)")
                if stats.packages == 0 {
                    lines.append("    ⚠  No <owner>/<repo>/ subdirs — nothing to index.")
                } else if stats.sidecars == stats.packages {
                    lines.append("    ✓  availability.json sidecars  (\(stats.sidecars)/\(stats.packages))")
                } else {
                    lines.append("    ⚠  availability.json sidecars  (\(stats.sidecars)/\(stats.packages))")
                    lines.append(
                        "       Missing \(stats.packages - stats.sidecars) — run "
                            + "`cupertino fetch --type packages --skip-metadata --skip-archives "
                            + "--annotate-availability` to backfill."
                    )
                }
            } else {
                lines.append("    ✗  \(packagesURL.path)  (missing — packages scope will be skipped)")
            }
            lines.append("")
        }

        if buildSamples {
            lines.append("  Samples (samples.db)")
            let samplesURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? SampleIndex.defaultSampleCodeDirectory
            if fm.fileExists(atPath: samplesURL.path) {
                let zipCount = (try? fm.contentsOfDirectory(atPath: samplesURL.path))?
                    .filter { $0.hasSuffix(".zip") }.count ?? 0
                lines.append("    ✓  \(samplesURL.path)  (\(zipCount) zips)")
                if zipCount == 0 {
                    lines.append("    ⚠  No zips — nothing to index.")
                } else {
                    lines.append("    (annotation runs inline during save — no preflight check needed)")
                }
            } else {
                lines.append("    ✗  \(samplesURL.path)  (missing — samples scope will be skipped)")
            }
            lines.append("")
        }

        return lines
    }

    /// Count `<owner>/<repo>/` directories under `packagesURL` and how
    /// many of them carry an `availability.json` sidecar (#219 stage 3).
    static func countPackagesAndSidecars(at packagesURL: URL) -> (packages: Int, sidecars: Int) {
        let fm = FileManager.default
        guard let owners = try? fm.contentsOfDirectory(
            at: packagesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var packageCount = 0
        var sidecarCount = 0
        for ownerURL in owners {
            guard (try? ownerURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let repos = try? fm.contentsOfDirectory(
                at: ownerURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for repoURL in repos {
                guard (try? repoURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                packageCount += 1
                let sidecarURL = repoURL.appendingPathComponent("availability.json")
                if fm.fileExists(atPath: sidecarURL.path) {
                    sidecarCount += 1
                }
            }
        }
        return (packageCount, sidecarCount)
    }
}
