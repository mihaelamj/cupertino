import ArgumentParser
import Foundation
import Indexer
import Logging
import RemoteSync
import SampleIndex
import Search
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

        @Option(name: .long, help: "Sample-code directory for `--samples` (#231).")
        var samplesDir: String?

        @Option(name: .long, help: "samples.db path override for `--samples` (#231).")
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
                Logging.ConsoleLogger.info("Aborted by user.")
                return
            }

            let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Constants.defaultBaseDirectory

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
                return true
            }

            Logging.ConsoleLogger.info("Continue? [Y/n] ")
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
        Logging.ConsoleLogger.info("🚀 Building Search Index from Remote\n")

        let effectiveBase = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory
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
            Logging.ConsoleLogger.info("🗑️  Removing existing database for clean re-index...")
            try FileManager.default.removeItem(at: searchDBURL)
        }

        Logging.ConsoleLogger.info("🗄️  Initializing search database...")
        let searchIndex = try await SearchModule.Index(dbPath: searchDBURL)

        let progressDisplay = RemoteSync.AnimatedProgress(barWidth: 20, useEmoji: true)
        let reporter = RemoteSync.ProgressReporter(display: progressDisplay)

        final class StatsTracker: @unchecked Sendable {
            var successCount = 0
            var errorCount = 0
        }
        let stats = StatsTracker()
        let startTime = Date()

        Logging.ConsoleLogger.output("")
        try await indexer.run(
            indexDocument: { uri, source, framework, title, content, jsonData in
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

        let elapsed = Date().timeIntervalSince(startTime)
        let docCount = try await searchIndex.documentCount()
        let frameworks = try await searchIndex.listFrameworks()

        reporter.finish(message: "")
        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Remote sync completed!")
        Logging.ConsoleLogger.info("   Total documents: \(docCount)")
        Logging.ConsoleLogger.info("   Frameworks: \(frameworks.count)")
        Logging.ConsoleLogger.info("   Indexed: \(stats.successCount) | Errors: \(stats.errorCount)")
        Logging.ConsoleLogger.info("   Time: \(Shared.Utils.Formatting.formatDuration(elapsed))")
        Logging.ConsoleLogger.info("   Database: \(searchDBURL.path)")
        Logging.ConsoleLogger.info("   Size: \(Self.formatFileSize(searchDBURL))")
        Logging.ConsoleLogger.info(
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

        Logging.ConsoleLogger.info("📋 Found previous session")
        Logging.ConsoleLogger.info("   Phase: \(state.phase.rawValue)")
        Logging.ConsoleLogger.info("   Progress: \(completedCount)/\(total) frameworks")
        if let current = state.currentFramework {
            Logging.ConsoleLogger.info(
                "   Current: \(current) (\(state.currentFileIndex)/\(state.filesTotal) files)"
            )
        }
        Logging.ConsoleLogger.output("")

        print("Resume from \(framework)? [Y/n] ", terminator: "")
        if let response = readLine()?.lowercased(), response == "n" || response == "no" {
            Logging.ConsoleLogger.info("🔄 Starting fresh...")
            try await indexer.clearState()
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                try FileManager.default.removeItem(at: searchDBURL)
            }
        } else {
            Logging.ConsoleLogger.info("▶️  Resuming...")
        }
    }
}
