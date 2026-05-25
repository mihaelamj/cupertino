import ArgumentParser
import Diagnostics
import Foundation
import Indexer
import Logging
import LoggingModels
import RemoteSync
import RemoteSyncModels
import SampleIndex
import SearchAPI
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
            abstract: "Rebuild per-source databases from on-disk sources",
            discussion: """
            Most users do NOT need this command. `cupertino setup` downloads the pre-built
            bundle and is the supported end-user workflow. `save` is for maintainers
            rebuilding the bundle, or advanced users rebuilding from a local crawl produced
            by `cupertino fetch`.

            Build target is selected per source via `--source <id>` (repeatable) or
            `--all` for every source. Valid source ids:

              apple-docs       Apple Developer Documentation
              swift-evolution  Swift Evolution proposals
              hig              Human Interface Guidelines
              apple-archive    Apple Archive legacy guides
              swift-org        Swift.org documentation
              swift-book       Swift Book (view-source, co-located with swift-org)
              samples          Apple Sample Code (rich schema + FTS rows)
              packages         Swift package metadata + source archives

            Sources whose input directory is absent or whose catalog is empty are
            skipped cleanly (`[source] skipped (no local corpus)`) and do not count as
            failures.

            A preflight summary is printed before indexing starts. Pass --yes (or pipe stdin)
            to skip the confirmation prompt. Run 'cupertino doctor --save' to preview the
            preflight output without writing any database.

            DISPATCH:
              `--source <id>` narrows the docs runner to ONLY the
              destination DB whose providers include that id.
              `--source apple-docs` builds apple-documentation.db
              alone; `--source hig` builds hig.db alone, etc.
              View-source pairs (`swift-org` + `swift-book`) co-locate
              in `swift-documentation.db`, so either id pulls both.
              `--source samples` runs both the Sample.Index rich-data
              pipeline AND the SampleCodeSource FTS rows under the
              single `apple-sample-code.db` file (one-DB-two-tracks
              per #1037). `--source packages` runs the standalone
              PackagesService against `packages.db`.

            EXAMPLES
              cupertino save --all                          # build every source's DB
              cupertino save --source apple-docs            # apple-documentation.db only
              cupertino save --source samples               # apple-sample-code.db (both tracks)
              cupertino save --source apple-docs --source hig   # two DBs
              cupertino save --remote                       # stream docs from GitHub
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

        @Option(
            name: .long,
            help: """
            Source id to build (repeatable). Valid ids: apple-docs, swift-evolution, \
            hig, apple-archive, swift-org, swift-book, samples, packages. Pass \
            `--source <id>` multiple times to build several sources. Mutually \
            exclusive with `--all`. At least one of `--source` or `--all` is \
            required (no scope flag = usage error post-#1037).
            """
        )
        var source: [String] = []

        @Flag(
            name: .long,
            help: "Build every source's DB. Mutually exclusive with `--source`."
        )
        var all: Bool = false

        @Option(name: .long, help: "Sample-code source directory (used with `--source samples`).")
        var samplesDir: String?

        @Option(name: .long, help: "apple-sample-code.db output path override (used with `--source samples`).")
        var samplesDB: String?

        @Flag(
            name: .long,
            help: "Force re-index of every sample under `--source samples` (existing rows wiped)."
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

        /// #722 — opt-in override of the concurrent-save gate. When a
        /// sibling `cupertino save` is already targeting one of our
        /// DBs, this flag authorises sending it SIGTERM (with a grace
        /// window for clean WAL flush, then SIGKILL fallback) before
        /// proceeding with our own save. Gated by a typed-confirmation
        /// prompt (TTY) or `--yes` (CI / scripted) — never
        /// unconditional, because nuking an in-flight multi-hour build
        /// by accident is exactly the class-of-bug this exists to
        /// prevent.
        @Flag(
            name: .long,
            help: """
            Authorise SIGTERM of any sibling `cupertino save` that targets the same DB(s). \
            Requires either an interactive typed-confirmation gate (type 'replace') or `--yes` \
            for non-interactive use (CI, scripts). Sends SIGTERM, waits for clean WAL flush, \
            SIGKILL fallback. Use sparingly — losing the sibling's in-flight work is the point \
            of the typed-confirmation gate.
            """
        )
        var forceReplace: Bool = false

        @Option(
            name: .long,
            help: """
            Seconds to wait between SIGTERM and SIGKILL when --force-replace terminates a \
            sibling save. Must be >= 0. The default of 30 is a practical floor for a \
            moderately-sized WAL; raise to 60 or higher when the sibling is near-completing a \
            multi-GB checkpoint and the default leaves SIGKILL landing mid-checkpoint (which is \
            what causes the corruption the gate exists to prevent). Passing 0 skips the grace \
            window entirely and SIGKILLs immediately — only use when you've already confirmed \
            the sibling is stuck.
            """
        )
        var forceReplaceGrace: Int = 30

        mutating func run() async throws {
            // #781: log the invocation banner before any other work so
            // long-running save logs preserve a paper trail of how the
            // process was launched. Combined with #780's per-line
            // timestamps, the first six lines of every save log give a
            // future operator everything they need to reproduce.
            Cupertino.Context.composition.logging.logInvocation()

            let recording = Cupertino.Context.composition.logging.recording

            // Warn when samples-scoped flags are passed but the
            // current invocation doesn't include the samples scope
            // (either via `--source samples` or under `--remote` which
            // bypasses samples entirely). The warning must fire BEFORE
            // the --remote short-circuit so a user running
            // `cupertino save --remote --samples-db /tmp/x.db` sees
            // that their --samples-db is being ignored, rather than
            // discovering it after a multi-hour remote stream
            // (critic round-8 finding #7).
            //
            // `--remote` mode always ignores samples (it only streams
            // docs from GitHub); during the resolver path we recompute
            // whether samples is in scope below.
            let samplesIsInScope = !remote && (all || source.contains(Shared.Constants.SourcePrefix.samples) ||
                source.contains(Shared.Constants.SourcePrefix.appleSampleCode))
            if !samplesIsInScope {
                let category: LoggingModels.Logging.Category = .samples
                // Critic round-9 finding #2: under --remote, the user
                // cannot follow the natural fix ("add --source samples")
                // because --source is mutex with --remote. Emit a
                // different hint that doesn't recommend a flag combo
                // that the binary will reject.
                let remediation = remote
                    ? "drop the flag (`--remote` streams docs only, no samples build)"
                    : "Either add `--source samples` or drop the flag"
                if samplesDir != nil {
                    recording.warning(
                        "⚠️  `--samples-dir` is ignored: \(remediation).",
                        category: category
                    )
                }
                if samplesDB != nil {
                    recording.warning(
                        "⚠️  `--samples-db` is ignored: \(remediation).",
                        category: category
                    )
                }
                if force {
                    let forceRemediation = remote
                        ? "drop the flag (`--remote` doesn't index samples)"
                        : "pass `--source samples` to use it. Currently ignored"
                    recording.warning(
                        "⚠️  `--force` only re-indexes the samples scope; \(forceRemediation).",
                        category: category
                    )
                }
            }

            // `--remote` is its own mode and bypasses the per-source
            // resolver. Pre-#1037 it could combine with the legacy
            // flag triplet (and just ignored the triplet); post-#1037
            // we surface the conflict as a usage error so the user
            // doesn't think their `--source` value is being honoured.
            if remote {
                guard source.isEmpty, !all else {
                    recording.error(
                        "❌ `--remote` is incompatible with `--source` / `--all`. " +
                            "`--remote` streams every docs source from GitHub; per-source " +
                            "selection is not yet supported in remote mode (#1037 follow-up)."
                    )
                    throw ExitCode.failure
                }
                try await runRemote()
                return
            }

            // Resolve `--source <id>` (repeatable) + `--all` into the
            // three internal bucket booleans (commit-1 of the
            // per-source CLI refactor: surface change only, dispatch
            // still bucket-level). Commit 2 will refactor
            // `LiveDocsIndexingRunner` to filter per source-id so
            // `--source apple-docs` builds ONLY apple-documentation.db
            // rather than the entire docs bucket.
            let selectedSourceIDs = try Self.resolveSelectedSourceIDs(source: source, all: all)
            let buildDocs = selectedSourceIDs.contains { Self.isDocsBucketSource($0) }
            let buildPackages = selectedSourceIDs.contains(Shared.Constants.SourcePrefix.packages)
            let buildSamples = selectedSourceIDs.contains(Shared.Constants.SourcePrefix.samples)

            // #253: gate on concurrent siblings before any preflight or
            // write. Detect other `cupertino save` processes targeting
            // the same DB(s) we're about to write and either continue
            // (TTY prompt → [c]), wait for them to exit (TTY → [w]), or
            // abort (TTY → [a], or non-TTY default).
            var myTargets: Set<SaveSiblingGate.Target> = []
            if buildDocs { myTargets.insert(.search) }
            if buildPackages { myTargets.insert(.packages) }
            if buildSamples { myTargets.insert(.samples) }

            switch SaveSiblingGate.gate(
                myTargets: myTargets,
                recording: recording,
                forceReplace: forceReplace,
                assumeYes: yes
            ) {
            case .proceed:
                break
            case .waitForSiblingsThenProceed(let pids):
                SaveSiblingGate.waitForSiblings(pids: pids, recording: recording)
            case .forceReplaceSiblings(let pids):
                // #722 — typed-confirmation gate already passed (or
                // `--yes` bypassed it). Terminate siblings + wait for
                // clean WAL flush before proceeding. Honour
                // `.stragglers` outcome — refuse to open the DB if
                // SIGKILL didn't take (otherwise we'd cascade into
                // `database is locked`).
                guard forceReplaceGrace >= 0 else {
                    recording.error(
                        "❌ --force-replace-grace must be >= 0 (got \(forceReplaceGrace)).",
                        category: .cli
                    )
                    throw ExitCode.failure
                }
                let outcome = SaveSiblingGate.terminateSiblings(
                    pids: pids,
                    graceSeconds: TimeInterval(forceReplaceGrace),
                    recording: recording
                )
                switch outcome {
                case .allTerminated:
                    break
                case .stragglers(let surviving):
                    recording.error(
                        "❌ Refusing to proceed — \(surviving.count) sibling save(s) still alive after SIGKILL: " +
                            "\(surviving.map(String.init).joined(separator: ", ")). " +
                            "Investigate (likely cross-user EPERM or stuck in D-state) before retrying.",
                        category: .cli
                    )
                    throw ExitCode.failure
                }
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
                try await runDocsIndexer(
                    effectiveBase: effectiveBase,
                    selectedSourceIDs: selectedSourceIDs
                )
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

        // MARK: - Per-source CLI resolution

        /// Valid `--source <id>` literals for `cupertino save`. Derived
        /// from the production source registry plus `packages` (which
        /// is excluded from the docs-runner grouping but is its own
        /// build target via PackagesService). Source of truth for the
        /// CLI's vocabulary; expanding the registry adds entries here
        /// automatically.
        static func validSourceIDs() -> Set<String> {
            var ids = Set(CLIImpl.makeProductionSourceRegistry().allEnabled.map(\.definition.id))
            // `packages` is in the registry today (PackagesSource lives
            // at `.packages`) but `groupedByDestinationDB(excluding:
            // [.packages])` filters it out of the docs runner because
            // its write pipeline is the standalone PackagesService.
            // Either way, allEnabled already includes it; this insert
            // is defensive in case a future refactor drops it from the
            // registry while keeping the standalone pipeline.
            ids.insert(Shared.Constants.SourcePrefix.packages)
            return ids
        }

        /// Aliases that the resolver accepts alongside the canonical
        /// `--source <id>` set. Cross-command consistency with
        /// `cupertino fetch --source apple-sample-code` (which has
        /// historically accepted both `apple-sample-code` and `samples`
        /// for the same source). Each alias maps onto its canonical id
        /// before validation.
        static let sourceIDAliases: [String: String] = [
            // Historical fetch-side alias for SampleCodeSource. The
            // canonical save-side id is `samples`
            // (`SourcePrefix.samples`); `apple-sample-code` is what
            // `cupertino fetch` accepts (`SourcePrefix.appleSampleCode`).
            // Maps onto `samples` so a user who runs
            // `cupertino fetch --source apple-sample-code` can run the
            // matching `cupertino save --source apple-sample-code`
            // without hitting an unknown-id error.
            Shared.Constants.SourcePrefix.appleSampleCode: Shared.Constants.SourcePrefix.samples,
        ]

        /// Source-ids that map to the docs-runner bucket (`buildDocs`).
        /// Every registry-enabled source EXCEPT `packages` lives there
        /// today; `samples` is in the docs runner via
        /// `SampleCodeSource` (which writes FTS rows to
        /// `apple-sample-code.db`) AND in the standalone samples
        /// runner (which writes the rich Sample.Index schema to the
        /// same file). Both fire together when `samples` is selected.
        static func isDocsBucketSource(_ id: String) -> Bool {
            id != Shared.Constants.SourcePrefix.packages
        }

        /// Validate + collapse `--source <id>` (repeatable) + `--all`
        /// into a `Set<String>` of selected ids. Throws a usage-error
        /// `ExitCode.failure` (with a logged message) on:
        ///   - both `--source` and `--all` passed (mutual exclusion)
        ///   - neither passed (no scope set; pre-#1037's "default to
        ///     everything" behaviour intentionally removed per the
        ///     "each source needs its own option" direction)
        ///   - `--source <id>` value not in `validSourceIDs()`
        ///
        /// `--all` returns the full `validSourceIDs()` set.
        static func resolveSelectedSourceIDs(
            source: [String],
            all: Bool
        ) throws -> Set<String> {
            let recording = Cupertino.Context.composition.logging.recording
            let valid = validSourceIDs()

            switch (source.isEmpty, all) {
            case (true, true):
                return valid
            case (false, true):
                recording.error(
                    "❌ `--source` and `--all` are mutually exclusive. Pass one but not both."
                )
                throw ExitCode.failure
            case (true, false):
                let sortedValid = valid.sorted().joined(separator: ", ")
                recording.error(
                    "❌ `cupertino save` requires either `--source <id>` (repeatable) " +
                        "or `--all`. Valid ids: \(sortedValid). Pre-#1037 binaries defaulted " +
                        "to building every DB; post-#1037 the scope is explicit."
                )
                throw ExitCode.failure
            case (false, false):
                // Apply aliases before validating so cross-command
                // names (e.g. fetch's `apple-sample-code`) collapse
                // onto canonical save-side ids.
                let normalized = Set(source.map { sourceIDAliases[$0] ?? $0 })
                let unknown = normalized.subtracting(valid).sorted()
                guard unknown.isEmpty else {
                    let sortedValid = valid.sorted().joined(separator: ", ")
                    recording.error(
                        "❌ Unknown `--source` value(s): \(unknown.joined(separator: ", ")). " +
                            "Valid ids: \(sortedValid)."
                    )
                    throw ExitCode.failure
                }
                return normalized
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
            try await searchIndex.indexDocument(Search.IndexDocumentParams(
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
        // #932: this Save path indexes via `RemoteSync.Indexer.run` +
        // `SearchIndexDocumentIndexer` which calls bare `indexDocument` on
        // the actor, NOT `indexItem`. Empty dict is correct.
        let searchIndex = try await SearchModule.Index(dbPath: searchDBURL, logger: Cupertino.Context.composition.logging.recording, indexers: [:], sourceLookup: .empty)

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
