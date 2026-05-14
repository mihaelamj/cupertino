import CoreJSONParser
import CoreProtocols
import CoreSampleCode
import Foundation
import LoggingModels
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
        Logging.LiveRecording().info("🔨 Building Search Index\n")

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
            docsIndexingRunner: LiveDocsIndexingRunner()
        ) { event in
            Self.handleDocsEvent(event, tracker: tracker)
        }
        Self.printDocsSummary(outcome: outcome)
    }

    /// Concrete `Search.DocsIndexingRunner` (GoF Strategy) used by
    /// `Indexer.DocsService`. Wraps `Search.Index` + `Search.IndexBuilder`.
    /// Lives at the CLI composition root so Indexer doesn't need
    /// `import Search` for these actor types.
    struct LiveDocsIndexingRunner: Search.DocsIndexingRunner {
        func run(
            input: Search.DocsIndexingInput,
            onProgress: @escaping @Sendable (Int, Int) -> Void
        ) async throws -> Search.DocsIndexingOutcome {
            let searchIndex = try await Search.Index(dbPath: input.searchDBPath, logger: Logging.LiveRecording())
            let builder = Search.IndexBuilder(
                searchIndex: searchIndex,
                metadata: nil,
                docsDirectory: input.docsDirectory,
                evolutionDirectory: input.evolutionDirectory,
                swiftOrgDirectory: input.swiftOrgDirectory,
                archiveDirectory: input.archiveDirectory,
                higDirectory: input.higDirectory,
                markdownStrategy: input.markdownStrategy,
                sampleCatalogProvider: input.sampleCatalogProvider, logger: Logging.LiveRecording()
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
                let path = Shared.Paths.live().sampleCodeDirectory
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
            Logging.LiveRecording().info("🗑️  Removing existing database for clean re-index...")
        case .initializingIndex:
            Logging.LiveRecording().info("🗄️  Initializing search database...")
        case .missingOptionalSource(let label, let url):
            Logging.LiveRecording().info("ℹ️  \(label) directory not found at \(url.path), skipping")
        case .availabilityMissing:
            Logging.LiveRecording().info("")
            Logging.LiveRecording().info("⚠️  Docs don't have availability data yet")
            Logging.LiveRecording().info("   Run 'cupertino fetch --type availability' first for best results")
            Logging.LiveRecording().info("")
        case .progress(let processed, let total, let percent):
            if percent - tracker.lastPercent >= 5.0 {
                Logging.LiveRecording().output(
                    "   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))"
                )
                tracker.lastPercent = percent
            }
        case .finished:
            break
        }
    }

    static func printDocsSummary(outcome: Indexer.DocsService.Outcome) {
        Logging.LiveRecording().output("")
        Logging.LiveRecording().info("✅ Search index built successfully!")
        Logging.LiveRecording().info("   Total documents: \(outcome.documentCount)")
        Logging.LiveRecording().info("   Frameworks: \(outcome.frameworkCount)")
        Logging.LiveRecording().info("   Database: \(outcome.searchDBPath.path)")
        Logging.LiveRecording().info("   Size: \(CLI.Command.Save.formatFileSize(outcome.searchDBPath))")
        Logging.LiveRecording().info(
            "\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.commandName) serve' to enable search"
        )
    }

    // MARK: - Packages

    func runPackagesIndexerSafely(effectiveBase: URL) async throws {
        let packagesRoot = packagesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)
        guard FileManager.default.fileExists(atPath: packagesRoot.path) else {
            Logging.LiveRecording().info(
                "ℹ️  packages directory not found at \(packagesRoot.path) — skipping packages step. "
                    + "Run `cupertino fetch --type packages` first."
            )
            return
        }
        try await runPackagesIndexer(packagesRoot: packagesRoot)
    }

    func runPackagesIndexer(packagesRoot: URL) async throws {
        let paths = Shared.Paths.live()
        let request = Indexer.PackagesService.Request(
            packagesRoot: packagesRoot,
            packagesDB: paths.packagesDatabase,
            clear: clear
        )

        _ = try await Indexer.PackagesService.run(
            request,
            packageIndexingRunner: LivePackageIndexingRunner()
        ) { event in
            Self.handlePackagesEvent(event)
        }
    }

    /// Concrete `Search.PackageIndexingRunner` (GoF Strategy) used by
    /// `Indexer.PackagesService`. Wraps `Search.PackageIndex` +
    /// `Search.PackageIndexer`. Lives at the CLI composition root so
    /// the Indexer SPM target doesn't import `Search` for these types.
    struct LivePackageIndexingRunner: Search.PackageIndexingRunner {
        func run(
            packagesRoot: URL,
            packagesDB: URL,
            onProgress: @escaping @Sendable (String, Int, Int) -> Void
        ) async throws -> Search.PackageIndexingOutcome {
            let startedAt = Date()
            let index = try await Search.PackageIndex(dbPath: packagesDB, logger: Logging.LiveRecording())
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
    }

    static func handlePackagesEvent(_ event: Indexer.PackagesService.Event) {
        switch event {
        case .starting(let root, let db):
            Logging.LiveRecording().info("🔨 Indexing packages from \(root.path) into \(db.path)")
        case .removingExistingDB(let url):
            Logging.LiveRecording().info("🗑️  --clear: removing existing \(url.lastPathComponent)")
        case .progress(let name, let done, let total):
            if done == 1 || done % 10 == 0 || done == total {
                Logging.LiveRecording().output(String(format: "📊 %d/%d — %@", done, total, name as NSString))
            }
        case .finished(let outcome):
            Self.printPackagesSummary(outcome: outcome)
        }
    }

    static func printPackagesSummary(outcome: Indexer.PackagesService.Outcome) {
        Logging.LiveRecording().output("")
        Logging.LiveRecording().info("✅ Package indexing completed")
        Logging.LiveRecording().info("   Packages indexed this run: \(outcome.packagesIndexed)")
        Logging.LiveRecording().info("   Packages failed: \(outcome.packagesFailed)")
        Logging.LiveRecording().info("   Files this run: \(outcome.totalFiles)")
        Logging.LiveRecording().info("   Bytes this run: \(outcome.totalBytes / 1024) KB")
        Logging.LiveRecording().info("   Duration: \(Int(outcome.durationSeconds))s")
        Logging.LiveRecording().info("")
        Logging.LiveRecording().info("   Total packages in DB: \(outcome.totalPackagesInDB)")
        Logging.LiveRecording().info("   Total files in DB: \(outcome.totalFilesInDB)")
        Logging.LiveRecording().info("   Total bytes in DB: \(outcome.totalBytesInDB / 1024) KB")
    }

    // MARK: - Samples

    func runSamplesIndexerSafely() async throws {
        // Path-DI composition sub-root (#535).
        let baseDir = Shared.Paths.live().baseDirectory
        let sampleCodeURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Sample.Index.sampleCodeDirectory(baseDirectory: baseDir)
        guard FileManager.default.fileExists(atPath: sampleCodeURL.path) else {
            Logging.LiveRecording().info(
                "ℹ️  sample-code directory not found at \(sampleCodeURL.path) — skipping samples step. "
                    + "Run `cupertino fetch --type samples` first."
            )
            return
        }
        try await runSamplesIndexer(sampleCodeURL: sampleCodeURL)
    }

    func runSamplesIndexer(sampleCodeURL: URL) async throws {
        // Path-DI composition sub-root (#535).
        let dbURL = samplesDB.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Sample.Index.databasePath(baseDirectory: Shared.Paths.live().baseDirectory)

        let request = Indexer.SamplesService.Request(
            sampleCodeDir: sampleCodeURL,
            samplesDB: dbURL,
            clear: clear,
            force: force
        )

        let tracker = ProgressTracker()
        _ = try await Indexer.SamplesService.run(
            request,
            samplesIndexingRunner: LiveSamplesIndexingRunner()
        ) { event in
            Self.handleSamplesEvent(event, tracker: tracker)
        }
    }

    /// Concrete `Sample.Index.SamplesIndexingRunner` (GoF Strategy)
    /// used by `Indexer.SamplesService`. Wraps `Sample.Index.Database` +
    /// `Sample.Index.Builder` + `Sample.Core.Catalog`. Lives at the
    /// CLI composition root so the Indexer SPM target doesn't import
    /// SampleIndex or CoreSampleCode for these types.
    struct LiveSamplesIndexingRunner: Sample.Index.SamplesIndexingRunner {
        func run(
            input: Sample.Index.SamplesIndexingInput,
            onPhase: @escaping @Sendable (Sample.Index.SamplesIndexingPhase) -> Void
        ) async throws -> Sample.Index.SamplesIndexingOutcome {
            let database = try await Sample.Index.Database(dbPath: input.samplesDB, logger: Logging.LiveRecording())
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
    }

    static func handleSamplesEvent(
        _ event: Indexer.SamplesService.Event,
        tracker: ProgressTracker
    ) {
        switch event {
        case .starting(let dir, let db):
            Logging.LiveRecording().output("📦 Cupertino - Sample Code Indexer\n")
            Logging.LiveRecording().output("   Sample code: \(dir.path)")
            Logging.LiveRecording().output("   Database: \(db.path)")
            Logging.LiveRecording().output("")
        case .removingExistingDB:
            Logging.LiveRecording().output("🗑️  Removing existing database for fresh index...")
        case .clearingExistingIndex:
            Logging.LiveRecording().output("🗑️  Clearing existing index...")
        case .existingIndexNotice(let projects, let files):
            Logging.LiveRecording().output("ℹ️  Found existing index with \(projects) projects, \(files) files")
            Logging.LiveRecording().output("   Use --force to reindex all, or --clear to start fresh")
            Logging.LiveRecording().output("")
        case .loadingCatalog:
            Logging.LiveRecording().output("📖 Loading sample code catalog...")
        case .catalogLoaded(let count):
            Logging.LiveRecording().output("   Found \(count) entries in catalog")
        case .indexingStart:
            Logging.LiveRecording().output("")
            Logging.LiveRecording().output("📇 Indexing sample code...")
            Logging.LiveRecording().output("")
        case .projectProgress(let name, let percent, let phase):
            if percent - tracker.lastPercent >= 5.0 || phase == .completed {
                let icon = phaseIcon(phase)
                Logging.LiveRecording().output("   [\(String(format: "%3.0f%%", percent))] \(icon) \(name)")
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
        Logging.LiveRecording().output("")
        Logging.LiveRecording().output("✅ Indexing complete!")
        Logging.LiveRecording().output("")
        Logging.LiveRecording().output("   Projects indexed: \(outcome.projectsIndexedThisRun)")
        Logging.LiveRecording().output("   Total projects: \(outcome.projectsTotal)")
        Logging.LiveRecording().output("   Total files: \(outcome.filesTotal)")
        Logging.LiveRecording().output("   Symbols extracted: \(outcome.symbolsTotal)")
        Logging.LiveRecording().output("   Imports captured: \(outcome.importsTotal)")
        Logging.LiveRecording().output("   Duration: \(Int(outcome.durationSeconds))s")
        Logging.LiveRecording().output("   Database: \(CLI.Command.Save.formatFileSize(outcome.samplesDBPath))")
    }

    /// Class wrapper so `@Sendable` callbacks can mutate `lastPercent`.
    /// Single-actor concurrency makes this safe in practice.
    final class ProgressTracker: @unchecked Sendable {
        var lastPercent = 0.0
    }
}
