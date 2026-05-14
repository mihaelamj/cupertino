import CoreJSONParser
import CoreProtocols
import CoreSampleCode
import Foundation
import Indexer
import Logging
import SampleIndex
import Search
import SearchModels
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Indexer dispatch + progress rendering (#244)

/// Per-source indexer dispatchers split out of `CLI.Command.Save.swift` so the
/// struct body stays under SwiftLint's `type_body_length` 300-line
/// ceiling. Each dispatcher converts CLI flags into an
/// `Indexer.<X>Service.Request`, runs the service, renders progress
/// events to the terminal, and prints a final summary.
extension CLI.Command.Save {
    // MARK: - Docs

    func runDocsIndexer(effectiveBase: URL) async throws {
        Logging.ConsoleLogger.info("🔨 Building Search Index\n")

        let request = Indexer.DocsService.Request(
            baseDir: effectiveBase,
            docsDir: docsDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            evolutionDir: evolutionDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            swiftOrgDir: swiftOrgDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            archiveDir: archiveDir.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            higDir: nil,
            searchDB: searchDB.map { URL(fileURLWithPath: $0).expandingTildeInPath },
            clear: clear
        )

        let tracker = ProgressTracker()
        let outcome = try await Indexer.DocsService.run(
            request,
            markdownStrategy: LiveMarkdownToStructuredPageStrategy(),
            sampleCatalogProvider: LiveSampleCatalogProvider(),
            docsIndexingRun: CLI.Command.Save.docsIndexingRun
        ) { event in
            Self.handleDocsEvent(event, tracker: tracker)
        }
        Self.printDocsSummary(outcome: outcome)
    }

    /// Concrete implementation of `Search.DocsIndexingRun` used by
    /// `Indexer.DocsService`. Wraps `Search.Index` + `Search.IndexBuilder`.
    /// Lives at the CLI composition root so Indexer doesn't need
    /// `import Search` for these actor types.
    static let docsIndexingRun: Search.DocsIndexingRun = { input, onProgress in
        let searchIndex = try await Search.Index(dbPath: input.searchDBPath)
        let builder = Search.IndexBuilder(
            searchIndex: searchIndex,
            metadata: nil,
            docsDirectory: input.docsDirectory,
            evolutionDirectory: input.evolutionDirectory,
            swiftOrgDirectory: input.swiftOrgDirectory,
            archiveDirectory: input.archiveDirectory,
            higDirectory: input.higDirectory,
            markdownStrategy: input.markdownStrategy,
            sampleCatalogProvider: input.sampleCatalogProvider
        )
        try await builder.buildIndex(clearExisting: input.clearExisting, onProgress: onProgress)
        let docCount = try await searchIndex.documentCount()
        let frameworks = try await searchIndex.listFrameworks()
        await searchIndex.disconnect()
        return Search.DocsIndexingOutcome(
            documentCount: docCount,
            frameworkCount: frameworks.count
        )
    }

    // MARK: - Markdown strategy adapter

    /// Concrete `Search.MarkdownToStructuredPageStrategy` (GoF Strategy)
    /// wrapping the `Core.JSONParser.MarkdownToStructuredPage.convert`
    /// static method. Lives at the CLI composition root so neither
    /// Search nor Indexer needs to import `CoreJSONParser` —
    /// the Search target sees only the protocol from SearchModels.
    struct LiveMarkdownToStructuredPageStrategy: Search.MarkdownToStructuredPageStrategy {
        func convert(markdown: String, url: URL?) -> Shared.Models.StructuredDocumentationPage? {
            Core.JSONParser.MarkdownToStructuredPage.convert(markdown, url: url)
        }
    }

    // MARK: - Sample catalog adapter

    /// Concrete `Search.SampleCatalogProvider` (GoF Strategy) that
    /// bridges `Sample.Core.Catalog` (the CoreSampleCode singleton)
    /// to the catalog-state shape the Search `SampleCodeStrategy`
    /// reads. Lives at the CLI composition root so neither Search nor
    /// Indexer needs to import `CoreSampleCode`.
    struct LiveSampleCatalogProvider: Search.SampleCatalogProvider {
        func fetch() async -> Search.SampleCatalogState {
            let entries = await Sample.Core.Catalog.allEntries
            let loaded = await Sample.Core.Catalog.loadedSource ?? .missing
            switch loaded {
            case .onDisk:
                let mapped = entries.map { entry in
                    Search.SampleCatalogEntry(
                        title: entry.title,
                        url: entry.url,
                        framework: entry.framework,
                        description: entry.description,
                        zipFilename: entry.zipFilename,
                        webURL: entry.webURL
                    )
                }
                return .loaded(entries: mapped)
            case .missing:
                let path = Shared.Constants.defaultSampleCodeDirectory
                    .appendingPathComponent(Sample.Core.Catalog.onDiskCatalogFilename)
                    .path
                return .missing(onDiskPath: path)
            }
        }
    }

    static func handleDocsEvent(
        _ event: Indexer.DocsService.Event,
        tracker: ProgressTracker
    ) {
        switch event {
        case .removingExistingDB:
            Logging.ConsoleLogger.info("🗑️  Removing existing database for clean re-index...")
        case .initializingIndex:
            Logging.ConsoleLogger.info("🗄️  Initializing search database...")
        case .missingOptionalSource(let label, let url):
            Logging.ConsoleLogger.info("ℹ️  \(label) directory not found at \(url.path), skipping")
        case .availabilityMissing:
            Logging.ConsoleLogger.info("")
            Logging.ConsoleLogger.info("⚠️  Docs don't have availability data yet")
            Logging.ConsoleLogger.info("   Run 'cupertino fetch --type availability' first for best results")
            Logging.ConsoleLogger.info("")
        case .progress(let processed, let total, let percent):
            if percent - tracker.lastPercent >= 5.0 {
                Logging.ConsoleLogger.output(
                    "   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))"
                )
                tracker.lastPercent = percent
            }
        case .finished:
            break
        }
    }

    static func printDocsSummary(outcome: Indexer.DocsService.Outcome) {
        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Search index built successfully!")
        Logging.ConsoleLogger.info("   Total documents: \(outcome.documentCount)")
        Logging.ConsoleLogger.info("   Frameworks: \(outcome.frameworkCount)")
        Logging.ConsoleLogger.info("   Database: \(outcome.searchDBPath.path)")
        Logging.ConsoleLogger.info("   Size: \(CLI.Command.Save.formatFileSize(outcome.searchDBPath))")
        Logging.ConsoleLogger.info(
            "\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.commandName) serve' to enable search"
        )
    }

    // MARK: - Packages

    func runPackagesIndexerSafely(effectiveBase: URL) async throws {
        let packagesRoot = packagesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)
        guard FileManager.default.fileExists(atPath: packagesRoot.path) else {
            Logging.ConsoleLogger.info(
                "ℹ️  packages directory not found at \(packagesRoot.path) — skipping packages step. "
                    + "Run `cupertino fetch --type packages` first."
            )
            return
        }
        try await runPackagesIndexer(packagesRoot: packagesRoot)
    }

    func runPackagesIndexer(packagesRoot: URL) async throws {
        let request = Indexer.PackagesService.Request(
            packagesRoot: packagesRoot,
            clear: clear
        )

        _ = try await Indexer.PackagesService.run(
            request,
            packageIndexingRun: Self.packageIndexingRun
        ) { event in
            Self.handlePackagesEvent(event)
        }
    }

    /// Concrete implementation of `Search.PackageIndexingRun` used by
    /// `Indexer.PackagesService`. Wraps `Search.PackageIndex` +
    /// `Search.PackageIndexer`. Lives at the CLI composition root so
    /// the Indexer SPM target doesn't import `Search` for these types.
    static let packageIndexingRun: Search.PackageIndexingRun = { packagesRoot, packagesDB, onProgress in
        let startedAt = Date()
        let index = try await Search.PackageIndex(dbPath: packagesDB)
        let indexer = Search.PackageIndexer(rootDirectory: packagesRoot, index: index)
        let stats = try await indexer.indexAll { name, done, total in
            onProgress(name, done, total)
        }
        let summary = try await index.summary()
        await index.disconnect()
        return Search.PackageIndexingOutcome(
            packagesIndexed: stats.packagesIndexed,
            packagesFailed: stats.packagesFailed,
            totalFiles: stats.totalFiles,
            totalBytes: stats.totalBytes,
            durationSeconds: Date().timeIntervalSince(startedAt),
            totalPackagesInDB: summary.packageCount,
            totalFilesInDB: summary.fileCount,
            totalBytesInDB: summary.bytesIndexed
        )
    }

    static func handlePackagesEvent(_ event: Indexer.PackagesService.Event) {
        switch event {
        case .starting(let root, let db):
            Logging.ConsoleLogger.info("🔨 Indexing packages from \(root.path) into \(db.path)")
        case .removingExistingDB(let url):
            Logging.ConsoleLogger.info("🗑️  --clear: removing existing \(url.lastPathComponent)")
        case .progress(let name, let done, let total):
            if done == 1 || done % 10 == 0 || done == total {
                Logging.ConsoleLogger.output(String(format: "📊 %d/%d — %@", done, total, name as NSString))
            }
        case .finished(let outcome):
            Self.printPackagesSummary(outcome: outcome)
        }
    }

    static func printPackagesSummary(outcome: Indexer.PackagesService.Outcome) {
        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Package indexing completed")
        Logging.ConsoleLogger.info("   Packages indexed this run: \(outcome.packagesIndexed)")
        Logging.ConsoleLogger.info("   Packages failed: \(outcome.packagesFailed)")
        Logging.ConsoleLogger.info("   Files this run: \(outcome.totalFiles)")
        Logging.ConsoleLogger.info("   Bytes this run: \(outcome.totalBytes / 1024) KB")
        Logging.ConsoleLogger.info("   Duration: \(Int(outcome.durationSeconds))s")
        Logging.ConsoleLogger.info("")
        Logging.ConsoleLogger.info("   Total packages in DB: \(outcome.totalPackagesInDB)")
        Logging.ConsoleLogger.info("   Total files in DB: \(outcome.totalFilesInDB)")
        Logging.ConsoleLogger.info("   Total bytes in DB: \(outcome.totalBytesInDB / 1024) KB")
    }

    // MARK: - Samples

    func runSamplesIndexerSafely() async throws {
        let sampleCodeURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Sample.Index.defaultSampleCodeDirectory
        guard FileManager.default.fileExists(atPath: sampleCodeURL.path) else {
            Logging.ConsoleLogger.info(
                "ℹ️  sample-code directory not found at \(sampleCodeURL.path) — skipping samples step. "
                    + "Run `cupertino fetch --type samples` first."
            )
            return
        }
        try await runSamplesIndexer(sampleCodeURL: sampleCodeURL)
    }

    func runSamplesIndexer(sampleCodeURL: URL) async throws {
        let dbURL = samplesDB.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Sample.Index.defaultDatabasePath

        let request = Indexer.SamplesService.Request(
            sampleCodeDir: sampleCodeURL,
            samplesDB: dbURL,
            clear: clear,
            force: force
        )

        let tracker = ProgressTracker()
        _ = try await Indexer.SamplesService.run(
            request,
            samplesIndexingRun: CLI.Command.Save.samplesIndexingRun
        ) { event in
            Self.handleSamplesEvent(event, tracker: tracker)
        }
    }

    /// Concrete implementation of `Sample.Index.SamplesIndexingRun` used
    /// by `Indexer.SamplesService`. Wraps `Sample.Index.Database` +
    /// `Sample.Index.Builder` + `Sample.Core.Catalog`. Lives at the CLI
    /// composition root so the Indexer SPM target doesn't import
    /// SampleIndex or CoreSampleCode for these types.
    static let samplesIndexingRun: Sample.Index.SamplesIndexingRun = { input, onPhase in
        let database = try await Sample.Index.Database(dbPath: input.samplesDB)
        if input.clear {
            onPhase(.clearingExistingIndex)
            try await database.clearAll()
        }

        let existingProjects = try await database.projectCount()
        let existingFiles = try await database.fileCount()
        if existingProjects > 0, !input.force, !input.clear {
            onPhase(.existingIndexNotice(projects: existingProjects, files: existingFiles))
        }

        onPhase(.loadingCatalog)
        let catalogEntries = await Sample.Core.Catalog.allEntries
        onPhase(.catalogLoaded(entryCount: catalogEntries.count))

        let entries = catalogEntries.map { entry in
            Sample.Index.SampleCodeEntryInfo(
                title: entry.title,
                description: entry.description,
                frameworks: [entry.framework],
                webURL: entry.webURL,
                zipFilename: entry.zipFilename
            )
        }

        onPhase(.indexingStart)
        let builder = Sample.Index.Builder(
            database: database,
            sampleCodeDirectory: input.sampleCodeDir
        )

        let startTime = Date()
        let indexed = try await builder.indexAll(
            entries: entries,
            forceReindex: input.force
        ) { progress in
            let phase: Sample.Index.SamplesIndexingPhase.ProgressPhase
            switch progress.status {
            case .extracting: phase = .extracting
            case .indexingFiles: phase = .indexingFiles
            case .completed: phase = .completed
            case .failed: phase = .failed
            }
            onPhase(.projectProgress(
                name: progress.currentProject,
                percent: progress.percentComplete,
                phase: phase
            ))
        }

        let duration = Date().timeIntervalSince(startTime)

        let finalProjects = try await database.projectCount()
        let finalFiles = try await database.fileCount()
        let finalSymbols = try await database.symbolCount()
        let finalImports = try await database.importCount()

        return Sample.Index.SamplesIndexingOutcome(
            projectsIndexedThisRun: indexed,
            projectsTotal: finalProjects,
            filesTotal: finalFiles,
            symbolsTotal: finalSymbols,
            importsTotal: finalImports,
            durationSeconds: duration
        )
    }

    static func handleSamplesEvent(
        _ event: Indexer.SamplesService.Event,
        tracker: ProgressTracker
    ) {
        switch event {
        case .starting(let dir, let db):
            Logging.Log.output("📦 Cupertino - Sample Code Indexer\n")
            Logging.Log.output("   Sample code: \(dir.path)")
            Logging.Log.output("   Database: \(db.path)")
            Logging.Log.output("")
        case .removingExistingDB:
            Logging.Log.output("🗑️  Removing existing database for fresh index...")
        case .clearingExistingIndex:
            Logging.Log.output("🗑️  Clearing existing index...")
        case .existingIndexNotice(let projects, let files):
            Logging.Log.output("ℹ️  Found existing index with \(projects) projects, \(files) files")
            Logging.Log.output("   Use --force to reindex all, or --clear to start fresh")
            Logging.Log.output("")
        case .loadingCatalog:
            Logging.Log.output("📖 Loading sample code catalog...")
        case .catalogLoaded(let count):
            Logging.Log.output("   Found \(count) entries in catalog")
        case .indexingStart:
            Logging.Log.output("")
            Logging.Log.output("📇 Indexing sample code...")
            Logging.Log.output("")
        case .projectProgress(let name, let percent, let phase):
            if percent - tracker.lastPercent >= 5.0 || phase == .completed {
                let icon = phaseIcon(phase)
                Logging.Log.output("   [\(String(format: "%3.0f%%", percent))] \(icon) \(name)")
                tracker.lastPercent = percent
            }
        case .finished(let outcome):
            Self.printSamplesSummary(outcome: outcome)
        }
    }

    private static func phaseIcon(_ phase: Indexer.SamplesService.Event.Phase) -> String {
        switch phase {
        case .extracting: return "📦"
        case .indexingFiles: return "📝"
        case .completed: return "✅"
        case .failed: return "❌"
        }
    }

    static func printSamplesSummary(outcome: Indexer.SamplesService.Outcome) {
        Logging.Log.output("")
        Logging.Log.output("✅ Indexing complete!")
        Logging.Log.output("")
        Logging.Log.output("   Projects indexed: \(outcome.projectsIndexedThisRun)")
        Logging.Log.output("   Total projects: \(outcome.projectsTotal)")
        Logging.Log.output("   Total files: \(outcome.filesTotal)")
        Logging.Log.output("   Symbols extracted: \(outcome.symbolsTotal)")
        Logging.Log.output("   Imports captured: \(outcome.importsTotal)")
        Logging.Log.output("   Duration: \(Int(outcome.durationSeconds))s")
        Logging.Log.output("   Database: \(CLI.Command.Save.formatFileSize(outcome.samplesDBPath))")
    }

    /// Class wrapper so `@Sendable` callbacks can mutate `lastPercent`.
    /// Single-actor concurrency makes this safe in practice.
    final class ProgressTracker: @unchecked Sendable {
        var lastPercent = 0.0
    }
}
