import ArgumentParser
import Diagnostics
import Foundation
import Indexer
import Logging
import LoggingModels
import RemoteSync
import RemoteSyncModels
import SampleIndex
import Search
import SearchModels
import SharedConstants

// MARK: - Save Command

/// Thin CLI wrapper around `Indexer.DocsService` / `Indexer.PackagesService`
/// / `Indexer.SamplesService` / `Indexer.Preflight` (#244). The
/// indexers + preflight pipeline live in the Indexer package; this
/// command parses flags, runs the preflight prompt, dispatches to the
/// requested scope, and renders progress.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct Save: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "save",
            abstract: "Rebuild search.db / packages.db / samples.db from on-disk sources",
            discussion: """
            Most users do NOT need this command — `cupertino setup` downloads the pre-built
            bundle and is the supported end-user workflow. `save` is for maintainers
            rebuilding the bundle, or advanced users rebuilding from a local crawl produced
            by `cupertino fetch`.

            Builds up to three local databases from whichever sources happen to be on disk:

              search.db   — Apple docs, Swift Evolution, HIG, Apple Archive, Swift.org, Swift Book
              packages.db — Swift package metadata and source archives
              samples.db  — Apple sample-code projects and their source files

            With no scope flag, all three databases are built. Sources whose input directory
            is absent or whose catalog is empty are skipped cleanly (`[source] skipped
            (no local corpus)`) and do not count as failures. Use --docs / --packages /
            --samples to build a subset.

            A preflight summary is printed before indexing starts. Pass --yes (or pipe stdin)
            to skip the confirmation prompt. Run 'cupertino doctor --save' to preview the
            preflight output without writing any database.

            EXAMPLES
              cupertino save                    # build all three DBs from whatever is on disk
              cupertino save --docs             # search.db only
              cupertino save --samples          # samples.db only
              cupertino save --packages         # packages.db only
              cupertino save --remote           # stream docs from GitHub (no local corpus needed)
            """
        )

        @Option(name: .long, help: "Base directory (auto-fills all directories from standard structure)")
        var baseDir: String?

        @Option(
            name: .long,
            help: "Optional. Directory containing crawled documentation. Maintainer workflow only; most users index from the pre-built bundle via `cupertino setup`."
        )
        var docsDir: String?

        @Option(name: .long, help: "Optional. Directory containing Swift Evolution proposals (maintainer workflow).")
        var evolutionDir: String?

        @Option(name: .long, help: "Optional. Directory containing Swift.org documentation (maintainer workflow).")
        var swiftOrgDir: String?

        @Option(name: .long, help: "Optional. Directory containing package READMEs (maintainer workflow).")
        var packagesDir: String?

        @Option(name: .long, help: "Optional. Directory containing Apple Archive documentation (maintainer workflow).")
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
            Swift.org + Swift Book). Defaults to ON when no scope flag is passed.
            """
        )
        var docs: Bool = false

        @Flag(
            name: .long,
            help: "Build packages.db from extracted package archives at `~/.cupertino/packages/<owner>/<repo>/`."
        )
        var packages: Bool = false

        @Flag(
            name: .long,
            help: "Build samples.db from extracted sample-code zips at `~/.cupertino/sample-code/`."
        )
        var samples: Bool = false

        @Option(name: .long, help: "Sample-code source directory (used with `--samples`).")
        var samplesDir: String?

        @Option(name: .long, help: "samples.db output path override (used with `--samples`).")
        var samplesDB: String?

        @Flag(
            name: .long,
            help: "Force re-index of every sample under `--samples` (existing rows wiped)."
        )
        var force: Bool = false

        @Flag(
            name: [.short, .long],
            help: "Skip the preflight summary + confirmation prompt. Auto-skipped when stdin isn't a TTY."
        )
        var yes: Bool = false

        @Flag(
            name: .long,
            help: """
            Run the full import pipeline against a throwaway temp database; emit \
            the per-document import log and final report, then delete the temp DB. \
            Used to verify that a corpus imports clean (0 collisions, 0 redundancy, \
            0 content lost) without touching the on-disk search.db. Honors all \
            other save flags (--docs-dir etc.).
            """
        )
        var dryRun: Bool = false

        mutating func run() async throws {
            if remote {
                try await runRemote()
                return
            }

            let scopeFlagsSet = docs || packages || samples
            let buildDocs = !scopeFlagsSet || docs
            let buildPackages = !scopeFlagsSet || packages
            let buildSamples = !scopeFlagsSet || samples

            // #253: gate on concurrent siblings before any preflight or
            // write. Detect other `cupertino save` processes targeting
            // the same DB(s) we're about to write and either continue
            // (TTY prompt → [c]), wait for them to exit (TTY → [w]), or
            // abort (TTY → [a], or non-TTY default).
            var myTargets: Set<SaveSiblingGate.Target> = []
            if buildDocs { myTargets.insert(.search) }
            if buildPackages { myTargets.insert(.packages) }
            if buildSamples { myTargets.insert(.samples) }

            let recording = Cupertino.Context.composition.logging.recording
            switch SaveSiblingGate.gate(myTargets: myTargets, recording: recording) {
            case .proceed:
                break
            case .waitForSiblingsThenProceed(let pids):
                SaveSiblingGate.waitForSiblings(pids: pids, recording: recording)
            case .abort(let reason):
                recording.info("❌ \(reason)", category: .cli)
                throw ExitCode.failure
            }

            // #673 Phase F — disk-space preflight. Refuse before opening
            // any DB if free disk wouldn't cover the operation's peak
            // write + safety margin. The 2026-05-16 corruption
            // (2.48 GB → 429 MB partial-write) happened because save
            // started on a 95%-full disk and crashed mid-FTS insert.
            // This check makes that class of bug impossible.
            try Self.runDiskPreflight(
                baseDir: baseDir,
                buildDocs: buildDocs,
                buildPackages: buildPackages,
                buildSamples: buildSamples,
                recording: recording
            )

            if !runPreflightAndConfirm(
                buildDocs: buildDocs,
                buildPackages: buildPackages,
                buildSamples: buildSamples
            ) {
                Cupertino.Context.composition.logging.recording.info("Aborted by user.")
                return
            }

            let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Paths.live().baseDirectory

            if buildDocs {
                try await runDocsIndexer(effectiveBase: effectiveBase)
            }
            if buildPackages {
                try await runPackagesIndexerSafely(effectiveBase: effectiveBase)
            }
            if buildSamples {
                try await runSamplesIndexerSafely(effectiveBase: effectiveBase)
            }
        }

        // MARK: - Indexer dispatchers moved to CLIImpl.Command.Save+Indexers.swift (#244)

        // MARK: - Preflight

        private func runPreflightAndConfirm(
            buildDocs: Bool,
            buildPackages: Bool,
            buildSamples: Bool
        ) -> Bool {
            let lines = Indexer.Preflight.preflightLines(
                paths: Shared.Paths.live(),
                buildDocs: buildDocs,
                buildPackages: buildPackages,
                buildSamples: buildSamples,
                baseDir: baseDir,
                docsDir: docsDir,
                samplesDir: samplesDir
            )
            Cupertino.Context.composition.logging.recording.info("🔍 Preflight check for `cupertino save`\n")
            for line in lines {
                Cupertino.Context.composition.logging.recording.info(line)
            }
            Cupertino.Context.composition.logging.recording.info("")

            if yes {
                Cupertino.Context.composition.logging.recording.info("--yes: skipping confirmation, continuing.\n")
                return true
            }
            guard isatty(fileno(stdin)) != 0 else {
                return true
            }

            Cupertino.Context.composition.logging.recording.info("Continue? [Y/n] ")
            guard let response = readLine() else { return true }
            let normalized = response.trimmingCharacters(in: .whitespaces).lowercased()
            return normalized.isEmpty || normalized == "y" || normalized == "yes"
        }

        // MARK: - #673 Phase F — disk-space preflight

        /// Refuse to start `cupertino save` if free disk wouldn't cover
        /// the operation's peak transient write + 10 % safety margin.
        ///
        /// Estimate sums the per-scope `Shared.Constants.DiskBudget`
        /// values for the scopes the user actually enabled (`--docs`
        /// alone is ~4 GB; all three is ~5 GB). The target volume is
        /// the same `effectiveBase` the save will write to, so a user
        /// passing `--base-dir /tmp/big-fast-disk` correctly probes
        /// `/tmp` not `~/`.
        ///
        /// Throws `Diagnostics.InsufficientDiskSpaceError` on refuse;
        /// `Cupertino.main` catches that and exits with `EX_IOERR` (74).
        /// `.warningLow` prints a one-line yellow hint but still
        /// returns so the save proceeds — refusing on a low-but-
        /// adequate disk would be a false positive for users who
        /// know they have just enough.
        private static func runDiskPreflight(
            baseDir: String?,
            buildDocs: Bool,
            buildPackages: Bool,
            buildSamples: Bool,
            recording: any LoggingModels.Logging.Recording
        ) throws {
            var estimate: Int64 = 0
            if buildDocs { estimate += Shared.Constants.DiskBudget.docsSaveBytes }
            if buildPackages { estimate += Shared.Constants.DiskBudget.packagesSaveBytes }
            if buildSamples { estimate += Shared.Constants.DiskBudget.samplesSaveBytes }
            guard estimate > 0 else { return }

            let target = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Paths.live().baseDirectory

            switch Diagnostics.DiskPreflight.check(targetDirectory: target, estimatedBytes: estimate) {
            case .ok:
                return
            case .warningLow(_, _, let freeFraction):
                let pct = String(format: "%.0f", freeFraction * 100)
                recording.info(
                    "⚠️  Free disk on the target volume is at \(pct) % — operation will proceed, but consider freeing space before the next reindex.",
                    category: .cli
                )
            case .refuseInsufficient(let needed, let free, let path):
                throw Diagnostics.InsufficientDiskSpaceError(
                    neededBytes: needed, freeBytes: free, path: path
                )
            }
        }

        // MARK: - Helpers

        static func formatFileSize(_ url: URL) -> String {
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
}

// MARK: - Remote mode

/// `--remote` streams documentation from GitHub instead of building from
/// a local corpus. Hasn't been lifted to `Indexer` yet because the
/// `RemoteSync.Indexer` interface is heavily UI-coupled (animated progress
/// bar, framework-by-framework status). Stays here until that pipeline
/// is consolidated under `Indexer.*Service`.
extension CLIImpl.Command.Save {
    /// GoF Strategy seam (`RemoteSync.DocumentIndexing`) that forwards each
    /// document fetched by `RemoteSync.Indexer.run` into the binary's
    /// `Search.Index` database.
    private struct SearchIndexDocumentIndexer: RemoteSync.DocumentIndexing {
        let searchIndex: SearchModule.Index

        func indexDocument(
            uri: String,
            source: String,
            framework: String?,
            title: String,
            content: String,
            jsonData: String?
        ) async throws {
            try await searchIndex.indexDocument(Search.Index.IndexDocumentParams(
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
            ))
        }
    }

    /// GoF Observer (`RemoteSync.IndexerProgressObserving`) that forwards
    /// progress ticks into the binary's animated `ProgressReporter`.
    private struct RemoteProgressObserver: RemoteSync.IndexerProgressObserving {
        let reporter: RemoteSync.ProgressReporter

        func observe(progress: RemoteSync.Progress) {
            reporter.update(progress)
        }
    }

    /// GoF Observer (`RemoteSync.IndexerDocumentObserving`) that bumps
    /// per-document success / error counters on a shared tracker.
    private struct RemoteDocumentObserver: RemoteSync.IndexerDocumentObserving {
        let stats: StatsTracker

        func observe(result: RemoteSync.IndexerResult) {
            if result.success {
                stats.bumpSuccess()
            } else {
                stats.bumpError()
            }
        }
    }

    /// Shared mutable counter for the remote-sync run. Lives inside the
    /// command type so the observer structs above can carry a reference.
    final class StatsTracker: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var successCount = 0
        private(set) var errorCount = 0

        func bumpSuccess() {
            lock.lock()
            defer { lock.unlock() }
            successCount += 1
        }

        func bumpError() {
            lock.lock()
            defer { lock.unlock() }
            errorCount += 1
        }
    }

    private func runRemote() async throws {
        Cupertino.Context.composition.logging.recording.info("🚀 Building Search Index from Remote\n")

        let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Paths.live().baseDirectory
        let searchDBURL = searchDB.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? effectiveBase.appendingPathComponent(Shared.Constants.FileName.searchDatabase)
        let stateFileURL = effectiveBase.appendingPathComponent("remote-save-state.json")

        let fetcher = RemoteSync.GitHubFetcher()
        let indexer = RemoteSync.Indexer(
            fetcher: fetcher,
            stateFileURL: stateFileURL,
            appVersion: Shared.Constants.App.version
        )

        if await indexer.hasResumableState() {
            try await handleResumableRemoteSession(
                indexer: indexer,
                searchDBURL: searchDBURL
            )
        } else if FileManager.default.fileExists(atPath: searchDBURL.path) {
            Cupertino.Context.composition.logging.recording.info("🗑️  Removing existing database for clean re-index...")
            try FileManager.default.removeItem(at: searchDBURL)
        }

        Cupertino.Context.composition.logging.recording.info("🗄️  Initializing search database...")
        let searchIndex = try await SearchModule.Index(dbPath: searchDBURL, logger: Cupertino.Context.composition.logging.recording)

        let progressDisplay = RemoteSync.AnimatedProgress(barWidth: 20, useEmoji: true)
        let reporter = RemoteSync.ProgressReporter(display: progressDisplay)

        let stats = StatsTracker()
        let startTime = Date()

        Cupertino.Context.composition.logging.recording.output("")
        try await indexer.run(
            documentIndexing: SearchIndexDocumentIndexer(searchIndex: searchIndex),
            progress: RemoteProgressObserver(reporter: reporter),
            document: RemoteDocumentObserver(stats: stats)
        )

        let elapsed = Date().timeIntervalSince(startTime)
        let docCount = try await searchIndex.documentCount()
        let frameworks = try await searchIndex.listFrameworks()

        reporter.finish(message: "")
        Cupertino.Context.composition.logging.recording.output("")
        Cupertino.Context.composition.logging.recording.info("✅ Remote sync completed!")
        Cupertino.Context.composition.logging.recording.info("   Total documents: \(docCount)")
        Cupertino.Context.composition.logging.recording.info("   Frameworks: \(frameworks.count)")
        Cupertino.Context.composition.logging.recording.info("   Indexed: \(stats.successCount) | Errors: \(stats.errorCount)")
        Cupertino.Context.composition.logging.recording.info("   Time: \(Shared.Utils.Formatting.formatDuration(elapsed))")
        Cupertino.Context.composition.logging.recording.info("   Database: \(searchDBURL.path)")
        Cupertino.Context.composition.logging.recording.info("   Size: \(Self.formatFileSize(searchDBURL))")
        Cupertino.Context.composition.logging.recording.info(
            "\n💡 Tip: Start the MCP server with '\(Shared.Constants.App.commandName) serve' to enable search"
        )
    }

    private func handleResumableRemoteSession(
        indexer: RemoteSync.Indexer,
        searchDBURL: URL
    ) async throws {
        let state = await indexer.getState()
        let completedCount = state.frameworksCompleted.count
        let total = state.frameworksTotal
        let framework = state.currentFramework ?? "unknown"

        Cupertino.Context.composition.logging.recording.info("📋 Found previous session")
        Cupertino.Context.composition.logging.recording.info("   Phase: \(state.phase.rawValue)")
        Cupertino.Context.composition.logging.recording.info("   Progress: \(completedCount)/\(total) frameworks")
        if let current = state.currentFramework {
            Cupertino.Context.composition.logging.recording.info(
                "   Current: \(current) (\(state.currentFileIndex)/\(state.filesTotal) files)"
            )
        }
        Cupertino.Context.composition.logging.recording.output("")

        print("Resume from \(framework)? [Y/n] ", terminator: "")
        if let response = readLine()?.lowercased(), response == "n" || response == "no" {
            Cupertino.Context.composition.logging.recording.info("🔄 Starting fresh...")
            try await indexer.clearState()
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                try FileManager.default.removeItem(at: searchDBURL)
            }
        } else {
            Cupertino.Context.composition.logging.recording.info("▶️  Resuming...")
        }
    }
}
