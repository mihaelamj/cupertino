import Foundation
import Indexer
import Logging
import SampleIndex
import SharedCore
import SharedConstants
import SharedUtils

// MARK: - Indexer dispatch + progress rendering (#244)

/// Per-source indexer dispatchers split out of `SaveCommand.swift` so the
/// struct body stays under SwiftLint's `type_body_length` 300-line
/// ceiling. Each dispatcher converts CLI flags into an
/// `Indexer.<X>Service.Request`, runs the service, renders progress
/// events to the terminal, and prints a final summary.
extension SaveCommand {
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
        let outcome = try await Indexer.DocsService.run(request) { event in
            Self.handleDocsEvent(event, tracker: tracker)
        }
        Self.printDocsSummary(outcome: outcome)
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
        Logging.ConsoleLogger.info("   Size: \(SaveCommand.formatFileSize(outcome.searchDBPath))")
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

        _ = try await Indexer.PackagesService.run(request) { event in
            Self.handlePackagesEvent(event)
        }
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
            ?? SampleIndex.defaultSampleCodeDirectory
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
            ?? SampleIndex.defaultDatabasePath

        let request = Indexer.SamplesService.Request(
            sampleCodeDir: sampleCodeURL,
            samplesDB: dbURL,
            clear: clear,
            force: force
        )

        let tracker = ProgressTracker()
        _ = try await Indexer.SamplesService.run(request) { event in
            Self.handleSamplesEvent(event, tracker: tracker)
        }
    }

    static func handleSamplesEvent(
        _ event: Indexer.SamplesService.Event,
        tracker: ProgressTracker
    ) {
        switch event {
        case .starting(let dir, let db):
            Log.output("📦 Cupertino - Sample Code Indexer\n")
            Log.output("   Sample code: \(dir.path)")
            Log.output("   Database: \(db.path)")
            Log.output("")
        case .removingExistingDB:
            Log.output("🗑️  Removing existing database for fresh index...")
        case .clearingExistingIndex:
            Log.output("🗑️  Clearing existing index...")
        case .existingIndexNotice(let projects, let files):
            Log.output("ℹ️  Found existing index with \(projects) projects, \(files) files")
            Log.output("   Use --force to reindex all, or --clear to start fresh")
            Log.output("")
        case .loadingCatalog:
            Log.output("📖 Loading sample code catalog...")
        case .catalogLoaded(let count):
            Log.output("   Found \(count) entries in catalog")
        case .indexingStart:
            Log.output("")
            Log.output("📇 Indexing sample code...")
            Log.output("")
        case .projectProgress(let name, let percent, let phase):
            if percent - tracker.lastPercent >= 5.0 || phase == .completed {
                let icon = phaseIcon(phase)
                Log.output("   [\(String(format: "%3.0f%%", percent))] \(icon) \(name)")
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
        Log.output("")
        Log.output("✅ Indexing complete!")
        Log.output("")
        Log.output("   Projects indexed: \(outcome.projectsIndexedThisRun)")
        Log.output("   Total projects: \(outcome.projectsTotal)")
        Log.output("   Total files: \(outcome.filesTotal)")
        Log.output("   Symbols extracted: \(outcome.symbolsTotal)")
        Log.output("   Imports captured: \(outcome.importsTotal)")
        Log.output("   Duration: \(Int(outcome.durationSeconds))s")
        Log.output("   Database: \(SaveCommand.formatFileSize(outcome.samplesDBPath))")
    }

    /// Class wrapper so `@Sendable` callbacks can mutate `lastPercent`.
    /// Single-actor concurrency makes this safe in practice.
    final class ProgressTracker: @unchecked Sendable {
        var lastPercent = 0.0
    }
}
