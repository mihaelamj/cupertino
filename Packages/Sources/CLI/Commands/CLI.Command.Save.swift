import ArgumentParser
import Foundation
import LoggingModels
import Indexer
import Logging
import RemoteSync
import SampleIndex
import Search
import SearchModels
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Save Command

/// Thin CLI wrapper around `Indexer.DocsService` / `Indexer.PackagesService`
/// / `Indexer.SamplesService` / `Indexer.Preflight` (#244). The
/// indexers + preflight pipeline live in the Indexer package; this
/// command parses flags, runs the preflight prompt, dispatches to the
/// requested scope, and renders progress.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLI.Command {
    struct Save: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "save",
            abstract: "Index fetched documentation into search.db, packages.db, and samples.db",
            discussion: """
            Builds up to three local databases from content downloaded by 'cupertino fetch':

              search.db   — Apple docs, Swift Evolution, HIG, Apple Archive, Swift.org, Swift Book
              packages.db — Swift package metadata and source archives
              samples.db  — Apple sample-code projects and their source files

            With no scope flag, all three databases are built (sources missing on disk are
            skipped with an info message). Use --docs / --packages / --samples to build a subset.

            A preflight summary is printed before indexing starts. Pass --yes (or pipe stdin)
            to skip the confirmation prompt. Run 'cupertino doctor --save' to preview the
            preflight output without writing any database.

            EXAMPLES
              cupertino save                    # build all three DBs
              cupertino save --docs             # search.db only
              cupertino save --samples          # samples.db only
              cupertino save --packages         # packages.db only
              cupertino save --remote           # stream docs from GitHub (no local corpus needed)
            """
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

        mutating func run() async throws {
            if remote {
                try await runRemote()
                return
            }

            let scopeFlagsSet = docs || packages || samples
            let buildDocs = !scopeFlagsSet || docs
            let buildPackages = !scopeFlagsSet || packages
            let buildSamples = !scopeFlagsSet || samples

            if !runPreflightAndConfirm(
                buildDocs: buildDocs,
                buildPackages: buildPackages,
                buildSamples: buildSamples
            ) {
                Logging.LiveRecording().info("Aborted by user.")
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
                try await runSamplesIndexerSafely()
            }
        }

        // MARK: - Indexer dispatchers moved to CLI.Command.Save+Indexers.swift (#244)

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
            Logging.LiveRecording().info("🔍 Preflight check for `cupertino save`\n")
            for line in lines {
                Logging.LiveRecording().info(line)
            }
            Logging.LiveRecording().info("")

            if yes {
                Logging.LiveRecording().info("--yes: skipping confirmation, continuing.\n")
                return true
            }
            guard isatty(fileno(stdin)) != 0 else {
                return true
            }

            Logging.LiveRecording().info("Continue? [Y/n] ")
            guard let response = readLine() else { return true }
            let normalized = response.trimmingCharacters(in: .whitespaces).lowercased()
            return normalized.isEmpty || normalized == "y" || normalized == "yes"
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
/// gets a callback-based shape.
extension CLI.Command.Save {
    private func runRemote() async throws {
        Logging.LiveRecording().info("🚀 Building Search Index from Remote\n")

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
            Logging.LiveRecording().info("🗑️  Removing existing database for clean re-index...")
            try FileManager.default.removeItem(at: searchDBURL)
        }

        Logging.LiveRecording().info("🗄️  Initializing search database...")
        let searchIndex = try await SearchModule.Index(dbPath: searchDBURL, logger: Logging.LiveRecording())

        let progressDisplay = RemoteSync.AnimatedProgress(barWidth: 20, useEmoji: true)
        let reporter = RemoteSync.ProgressReporter(display: progressDisplay)

        final class StatsTracker: @unchecked Sendable {
            var successCount = 0
            var errorCount = 0
        }
        let stats = StatsTracker()
        let startTime = Date()

        Logging.LiveRecording().output("")
        try await indexer.run(
            indexDocument: { uri, source, framework, title, content, jsonData in
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

        let elapsed = Date().timeIntervalSince(startTime)
        let docCount = try await searchIndex.documentCount()
        let frameworks = try await searchIndex.listFrameworks()

        reporter.finish(message: "")
        Logging.LiveRecording().output("")
        Logging.LiveRecording().info("✅ Remote sync completed!")
        Logging.LiveRecording().info("   Total documents: \(docCount)")
        Logging.LiveRecording().info("   Frameworks: \(frameworks.count)")
        Logging.LiveRecording().info("   Indexed: \(stats.successCount) | Errors: \(stats.errorCount)")
        Logging.LiveRecording().info("   Time: \(Shared.Utils.Formatting.formatDuration(elapsed))")
        Logging.LiveRecording().info("   Database: \(searchDBURL.path)")
        Logging.LiveRecording().info("   Size: \(Self.formatFileSize(searchDBURL))")
        Logging.LiveRecording().info(
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

        Logging.LiveRecording().info("📋 Found previous session")
        Logging.LiveRecording().info("   Phase: \(state.phase.rawValue)")
        Logging.LiveRecording().info("   Progress: \(completedCount)/\(total) frameworks")
        if let current = state.currentFramework {
            Logging.LiveRecording().info(
                "   Current: \(current) (\(state.currentFileIndex)/\(state.filesTotal) files)"
            )
        }
        Logging.LiveRecording().output("")

        print("Resume from \(framework)? [Y/n] ", terminator: "")
        if let response = readLine()?.lowercased(), response == "n" || response == "no" {
            Logging.LiveRecording().info("🔄 Starting fresh...")
            try await indexer.clearState()
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                try FileManager.default.removeItem(at: searchDBURL)
            }
        } else {
            Logging.LiveRecording().info("▶️  Resuming...")
        }
    }
}
