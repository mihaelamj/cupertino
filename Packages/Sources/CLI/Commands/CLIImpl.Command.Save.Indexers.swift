import CoreJSONParser
import CoreProtocols
import CoreSampleCode
import Foundation
import Indexer
import Logging
import LoggingModels
import SampleIndex
import Search
import SearchModels
import SharedConstants

// MARK: - Indexer dispatch + progress rendering (#244)

/// Per-source indexer dispatchers split out of `CLIImpl.Command.Save.swift` so the
/// struct body stays under SwiftLint's `type_body_length` 300-line
/// ceiling. Each dispatcher converts CLI flags into an
/// `Indexer.<X>Service.Request`, runs the service, renders progress
/// events to the terminal, and prints a final summary.
extension CLIImpl.Command.Save {
    // MARK: - Docs

    func runDocsIndexer(effectiveBase: URL) async throws {
        Cupertino.Context.composition.logging.recording.info("🔨 Building Search Index\n")

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

        // Path-DI composition sub-root (#535): catalog actor takes
        // the resolved sample-code directory at construction.
        let sampleCatalogActor = Sample.Core.Catalog(
            sampleCodeDirectory: Shared.Paths.live().sampleCodeDirectory
        )

        let tracker = ProgressTracker()
        let outcome = try await Indexer.DocsService.run(
            request,
            markdownStrategy: LiveMarkdownToStructuredPageStrategy(),
            sampleCatalogProvider: LiveSampleCatalogProvider(catalog: sampleCatalogActor),
            docsIndexingRunner: LiveDocsIndexingRunner()
        ) { event in
            Self.handleDocsEvent(event, tracker: tracker)
        }
        Self.printDocsSummary(outcome: outcome)
    }

    /// Adapter bridging the closure-shaped `onProgress` parameter on the
    /// `Search.DocsIndexingRun` protocol (defined in `SearchModels`) to the
    /// `Search.IndexingProgressReporting` protocol that `Search.IndexBuilder`
    /// now expects. The CLI is the composition root for this seam; the
    /// adapter struct is the only place the closure-to-protocol bridge
    /// lives. Future work can purge the closure from `DocsIndexingRun.run`
    /// itself.
    private struct ProgressCallbackToReporter: Search.IndexingProgressReporting {
        let onProgress: @Sendable (Int, Int) -> Void

        func report(processed: Int, total: Int) {
            onProgress(processed, total)
        }
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
            let searchIndex = try await Search.Index(dbPath: input.searchDBPath, logger: Cupertino.Context.composition.logging.recording)
            let builder = Search.IndexBuilder(
                searchIndex: searchIndex,
                metadata: nil,
                docsDirectory: input.docsDirectory,
                evolutionDirectory: input.evolutionDirectory,
                swiftOrgDirectory: input.swiftOrgDirectory,
                archiveDirectory: input.archiveDirectory,
                higDirectory: input.higDirectory,
                markdownStrategy: input.markdownStrategy,
                sampleCatalogProvider: input.sampleCatalogProvider, logger: Cupertino.Context.composition.logging.recording
            )
            try await builder.buildIndex(
                clearExisting: input.clearExisting,
                onProgress: ProgressCallbackToReporter(onProgress: onProgress)
            )
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
    /// bridges `Sample.Core.Catalog` (a per-install actor, post-#535)
    /// to the catalog-state shape the Search `SampleCodeStrategy`
    /// reads. Lives at the CLI composition root so neither Search nor
    /// Indexer needs to import `CoreSampleCode`.
    struct LiveSampleCatalogProvider: Search.SampleCatalogProvider {
        let catalog: Sample.Core.Catalog

        func fetch() async -> Search.SampleCatalogState {
            let entries = await catalog.allEntries
            let loaded = await catalog.loadedSource ?? .missing
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
            Cupertino.Context.composition.logging.recording.info("🗑️  Removing existing database for clean re-index...")
        case .initializingIndex:
            Cupertino.Context.composition.logging.recording.info("🗄️  Initializing search database...")
        case .missingOptionalSource(let label, let url):
            Cupertino.Context.composition.logging.recording.info("ℹ️  \(label) directory not found at \(url.path), skipping")
        case .availabilityMissing:
            Cupertino.Context.composition.logging.recording.info("")
            Cupertino.Context.composition.logging.recording.info("⚠️  Docs don't have availability data yet")
            Cupertino.Context.composition.logging.recording.info("   Run 'cupertino fetch --type availability' first for best results")
            Cupertino.Context.composition.logging.recording.info("")
        case .progress(let processed, let total, let percent):
            if percent - tracker.lastPercent >= 5.0 {
                Cupertino.Context.composition.logging.recording.output(
                    "   \(String(format: "%.0f%%", percent)) complete (\(processed)/\(total))"
                )
                tracker.lastPercent = percent
            }
        case .finished:
            break
        }
    }

    static func printDocsSummary(outcome: Indexer.DocsService.Outcome) {
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.info("✅ Search index built successfully!")
        Cupertino.Context.composition.logging.recording.info("   Total documents: \(outcome.documentCount)")
        Cupertino.Context.composition.logging.recording.info("   Frameworks: \(outcome.frameworkCount)")
        Cupertino.Context.composition.logging.recording.info("   Database: \(outcome.searchDBPath.path)")
        Cupertino.Context.composition.logging.recording.info("   Size: \(CLIImpl.Command.Save.formatFileSize(outcome.searchDBPath))")
        Cupertino.Context.composition.logging.recording.info(
            "\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.commandName) serve' to enable search"
        )
    }

    // MARK: - Packages

    func runPackagesIndexerSafely(effectiveBase: URL) async throws {
        let packagesRoot = packagesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.Directory.packages)
        guard FileManager.default.fileExists(atPath: packagesRoot.path) else {
            Cupertino.Context.composition.logging.recording.info(
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
            let index = try await Search.PackageIndex(dbPath: packagesDB, logger: Cupertino.Context.composition.logging.recording)
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
            Cupertino.Context.composition.logging.recording.info("🔨 Indexing packages from \(root.path) into \(db.path)")
        case .removingExistingDB(let url):
            Cupertino.Context.composition.logging.recording.info("🗑️  --clear: removing existing \(url.lastPathComponent)")
        case .progress(let name, let done, let total):
            if done == 1 || done % 10 == 0 || done == total {
                Cupertino.Context.composition.logging.recording.output(String(format: "📊 %d/%d — %@", done, total, name as NSString))
            }
        case .finished(let outcome):
            Self.printPackagesSummary(outcome: outcome)
        }
    }

    static func printPackagesSummary(outcome: Indexer.PackagesService.Outcome) {
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.info("✅ Package indexing completed")
        Cupertino.Context.composition.logging.recording.info("   Packages indexed this run: \(outcome.packagesIndexed)")
        Cupertino.Context.composition.logging.recording.info("   Packages failed: \(outcome.packagesFailed)")
        Cupertino.Context.composition.logging.recording.info("   Files this run: \(outcome.totalFiles)")
        Cupertino.Context.composition.logging.recording.info("   Bytes this run: \(outcome.totalBytes / 1024) KB")
        Cupertino.Context.composition.logging.recording.info("   Duration: \(Int(outcome.durationSeconds))s")
        Cupertino.Context.composition.logging.recording.info("")
        Cupertino.Context.composition.logging.recording.info("   Total packages in DB: \(outcome.totalPackagesInDB)")
        Cupertino.Context.composition.logging.recording.info("   Total files in DB: \(outcome.totalFilesInDB)")
        Cupertino.Context.composition.logging.recording.info("   Total bytes in DB: \(outcome.totalBytesInDB / 1024) KB")
    }

    // MARK: - Samples

    func runSamplesIndexerSafely() async throws {
        // Path-DI composition sub-root (#535).
        let baseDir = Shared.Paths.live().baseDirectory
        let sampleCodeURL = samplesDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Sample.Index.sampleCodeDirectory(baseDirectory: baseDir)
        guard FileManager.default.fileExists(atPath: sampleCodeURL.path) else {
            Cupertino.Context.composition.logging.recording.info(
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
    /// Adapter bridging the closure-shaped `onPhase` parameter on the
    /// `Sample.Index.SamplesIndexingRunner` protocol (defined in
    /// `SampleIndexModels`) to the `Sample.Index.ProgressReporting`
    /// Observer protocol that `Sample.Index.Builder` now expects. The CLI
    /// is the composition root for this seam; the adapter struct is the
    /// only place the closure-to-protocol bridge lives. Future work can
    /// purge the closure from `SamplesIndexingRunner.run` itself.
    private struct SamplesProgressReporter: Sample.Index.ProgressReporting {
        let onPhase: @Sendable (Sample.Index.SamplesIndexingPhase) -> Void

        func report(progress: Sample.Index.IndexProgress) {
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
    }

    struct LiveSamplesIndexingRunner: Sample.Index.SamplesIndexingRunner {
        func run(
            input: Sample.Index.SamplesIndexingInput,
            onPhase: @escaping @Sendable (Sample.Index.SamplesIndexingPhase) -> Void
        ) async throws -> Sample.Index.SamplesIndexingOutcome {
            let database = try await Sample.Index.Database(dbPath: input.samplesDB, logger: Cupertino.Context.composition.logging.recording)
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
            // Path-DI (#535): construct catalog actor with the input's
            // sample-code directory rather than reaching for the singleton.
            let catalog = Sample.Core.Catalog(sampleCodeDirectory: input.sampleCodeDir)
            let catalogEntries = await catalog.allEntries
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
            let reporter = SamplesProgressReporter(onPhase: onPhase)
            let indexed = try await builder.indexAll(
                entries: entries,
                forceReindex: input.force,
                progress: reporter
            )

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
            Cupertino.Context.composition.logging.recording.output("📦 Cupertino - Sample Code Indexer\n")
            Cupertino.Context.composition.logging.recording.output("   Sample code: \(dir.path)")
            Cupertino.Context.composition.logging.recording.output("   Database: \(db.path)")
            Cupertino.Context.composition.logging.recording.output("")
        case .removingExistingDB:
            Cupertino.Context.composition.logging.recording.output("🗑️  Removing existing database for fresh index...")
        case .clearingExistingIndex:
            Cupertino.Context.composition.logging.recording.output("🗑️  Clearing existing index...")
        case .existingIndexNotice(let projects, let files):
            Cupertino.Context.composition.logging.recording.output("ℹ️  Found existing index with \(projects) projects, \(files) files")
            Cupertino.Context.composition.logging.recording.output("   Use --force to reindex all, or --clear to start fresh")
            Cupertino.Context.composition.logging.recording.output("")
        case .loadingCatalog:
            Cupertino.Context.composition.logging.recording.output("📖 Loading sample code catalog...")
        case .catalogLoaded(let count):
            Cupertino.Context.composition.logging.recording.output("   Found \(count) entries in catalog")
        case .indexingStart:
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output("📇 Indexing sample code...")
            Cupertino.Context.composition.logging.recording.output("")
        case .projectProgress(let name, let percent, let phase):
            if percent - tracker.lastPercent >= 5.0 || phase == .completed {
                let icon = phaseIcon(phase)
                Cupertino.Context.composition.logging.recording.output("   [\(String(format: "%3.0f%%", percent))] \(icon) \(name)")
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
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.output("✅ Indexing complete!")
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.output("   Projects indexed: \(outcome.projectsIndexedThisRun)")
        Cupertino.Context.composition.logging.recording.output("   Total projects: \(outcome.projectsTotal)")
        Cupertino.Context.composition.logging.recording.output("   Total files: \(outcome.filesTotal)")
        Cupertino.Context.composition.logging.recording.output("   Symbols extracted: \(outcome.symbolsTotal)")
        Cupertino.Context.composition.logging.recording.output("   Imports captured: \(outcome.importsTotal)")
        Cupertino.Context.composition.logging.recording.output("   Duration: \(Int(outcome.durationSeconds))s")
        Cupertino.Context.composition.logging.recording.output("   Database: \(CLIImpl.Command.Save.formatFileSize(outcome.samplesDBPath))")
    }

    /// Class wrapper so `@Sendable` callbacks can mutate `lastPercent`.
    /// Single-actor concurrency makes this safe in practice.
    final class ProgressTracker: @unchecked Sendable {
        var lastPercent = 0.0
    }
}
