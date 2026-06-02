import ArgumentParser
import Diagnostics
import Distribution
import Foundation
import Logging
import LoggingModels
import SampleIndexModels
import SharedConstants

// MARK: - Setup Command

/// Thin CLI wrapper around `Distribution.SetupService` (#246). The
/// download/extract/version pipeline lives in the Distribution package;
/// this command parses flags, subscribes to progress events, and renders
/// the spinner + progress bar + final summary.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct Setup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup",
            abstract: "Download every cupertino database in one go"
        )

        @Option(name: .long, help: "Base directory for databases")
        var baseDir: String?

        @Flag(name: .long, help: "Skip the download and keep whatever databases are already installed")
        var keepExisting: Bool = false

        /// Closure-free observer that forwards every
        /// `Distribution.SetupService.Event` to the `SetupRenderer`'s
        /// `handle(_:)` dispatcher. Replaces the previous trailing-closure
        /// pattern at the `Distribution.SetupService.run` call site.
        private struct SetupEventObserver: Distribution.SetupService.EventObserving {
            let renderer: SetupRenderer

            func observe(event: Distribution.SetupService.Event) {
                renderer.handle(event)
            }
        }

        mutating func validate() throws {
        if force {
            throw ValidationError("--force was removed in v1.2.0. cupertino setup overwrites by default; pass --keep-existing if you want to preserve already-installed databases.")
        }
    }

 func run() async throws {
            // #781: invocation banner before any other work.
            Cupertino.Context.composition.logging.logInvocation()

            Cupertino.Context.composition.logging.recording.info("📦 Cupertino Setup\n")

            // Path-DI composition sub-root (#535): construct once at the top
            // of run(), then thread explicit URLs into every consumer.
            let paths = Shared.Paths.live()
            let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? paths.baseDirectory

            // #673 Phase F — disk-space preflight. Setup downloads a
            // ~850 MB zip + extracts ~2.7 GB of DBs + transient working
            // tree. Refuse before any download starts if free disk would
            // run out mid-extract — the partial-extract state is the
            // same corruption shape Phase F was filed to prevent.
            let recording = Cupertino.Context.composition.logging.recording
            switch Diagnostics.DiskPreflight.check(
                targetDirectory: baseURL,
                estimatedBytes: Shared.Constants.DiskBudget.setupBytes
            ) {
            case .ok:
                break
            case .warningLow(_, _, let freeFraction):
                let pct = String(format: "%.0f", freeFraction * 100)
                recording.info(
                    "⚠️  Free disk on the target volume is at \(pct) % — setup will proceed, but consider freeing space before the next bundle update.",
                    category: .cli
                )
            case .refuseInsufficient(let needed, let free, let path):
                throw Diagnostics.InsufficientDiskSpaceError(
                    neededBytes: needed, freeBytes: free, path: path
                )
            }

            let renderer = SetupRenderer()
            // Composition root for the per-DB descriptor list driving
            // `cupertino setup`. Order is load-bearing because
            // `Distribution.SetupService.Outcome.databases` is order-sensitive
            // and the success-summary printer iterates this order.
            //
            // Adding a 4th cupertino-managed database to `cupertino setup`
            // requires:
            //   1. one new `static let <name>: DatabaseDescriptor` in
            //      `Shared.Models.DatabaseDescriptor`
            //   2. one append below
            // No edit to `Distribution.SetupService.run` required; the
            // service iterates `request.required` end-to-end.
            //
            // Out-of-scope for this seam (still requires further edits
            // to surface a new DB across the rest of the CLI): write a
            // new `Distribution.DatabaseHealthCheck` conformer (via the
            // #931 strategy seam, already merged) and append it to the
            // Doctor command's healthChecks list; update the
            // `printSchemaVersions` entries array in `Doctor.swift`
            // (each DB uses a different URL-resolution helper, so this
            // doesn't yet plug in declaratively); per-descriptor
            // download URLs (the bundle currently ships every DB
            // inside `cupertino-databases-vX.Y.Z.zip`).
            // #1037 part 4: bundle/reader filename alignment. The
            // `.samples` descriptor (filename `samples.db`) was the
            // pre-#1037 bundle target; post-#1037 the canonical filename
            // is `apple-sample-code.db` (descriptor `.appleSampleCode`)
            // because `Sample.Index.databasePath` and
            // `SampleCodeSource.destinationDB` both resolve there. The
            // bundle must extract under the same filename the readers
            // open, otherwise every fresh-install user gets the
            // sample-code feature dark. Legacy bundles built by pre-#1037
            // ReleaseTool runs still ship `samples.db`; the migration
            // hook (see `runPerSourceDBSplitMigrationIfNeeded` /
            // `migrateLegacySamplesDatabaseIfNeeded` below) detects and
            // renames that filename to the new one on first post-#1037
            // setup invocation.
            // Pluggability anchor: the bundle's required-descriptor list
            // is derived from `CLIImpl.makeProductionSourceRegistry()`
            // (every enabled source's `destinationDB`). Adding a new
            // source = one register call + one source file, with this
            // setup hard-fail check picking up the new DB automatically.
            // Pre-rename this line hardcoded `[.search, .appleSampleCode,
            // .packages]` — the pre-#1037 3-DB bundle shape.
            let request = Distribution.SetupService.Request(
                baseDir: baseURL,
                keepExisting: keepExisting,
                required: CLIImpl.bundleRequiredDescriptors()
            )

            do {
                let outcome = try await Distribution.SetupService.run(
                    request,
                    events: SetupEventObserver(renderer: renderer)
                )
                renderer.printFinalSummary(outcome: outcome)

                // Step 6c-iii: per-source DB split migration hook.
                // After the bundle download + extract completes, check
                // whether the just-extracted `search.db` needs splitting
                // into per-source DBs and run the migrator if so. The
                // migration is a one-shot: subsequent runs see
                // `alreadyMigrated` and skip cleanly.
                try await Self.runPerSourceDBSplitMigrationIfNeeded(
                    baseDirectory: baseURL,
                    logger: Cupertino.Context.composition.logging.recording
                )

                // #1037 part 4: legacy samples.db filename migration.
                // Pre-#1037 bundles shipped the sample-code DB as
                // `samples.db`; post-#1037 the canonical filename is
                // `apple-sample-code.db`. Detect a leftover legacy
                // file on disk and rename it to the new name so
                // readers (`cupertino list-samples`, etc) find it.
                // No-op when only the new file exists (fresh install
                // on a post-#1037 bundle) or only the legacy file is
                // gone (already-migrated steady state).
                Self.migrateLegacySamplesDatabaseIfNeeded(
                    baseDirectory: baseURL,
                    logger: Cupertino.Context.composition.logging.recording
                )
            } catch {
                Cupertino.Context.composition.logging.recording.error("❌ Setup failed: \(error)")
                throw ExitCode.failure
            }
        }

        // MARK: - Per-source DB split migration (step 6c-iii)

        /// Detects whether a legacy `search.db` needs splitting into
        /// per-source DBs; runs the migration if so; emits user-facing
        /// progress lines. Wraps any `MigrationError` as a non-fatal
        /// warning (the legacy file stays intact; the user can re-run
        /// `cupertino setup` to retry).
        ///
        /// The split is mandatory for users whose installed bundle is
        /// pre-v1.3.0 (one shared search.db). Post-v1.3.0 bundles ship
        /// the 6 per-source DBs directly + the migrator's `detect()`
        /// returns `.noLegacyDBFound` (no legacy file present), so this
        /// helper short-circuits cleanly.
        static func runPerSourceDBSplitMigrationIfNeeded(
            baseDirectory: URL,
            logger: any LoggingModels.Logging.Recording
        ) async throws {
            let registry = CLIImpl.makeProductionSourceRegistry()
            let detection = Distribution.PerSourceDBSplitMigrator.detect(
                inBaseDirectory: baseDirectory,
                registry: registry
            )

            switch detection {
            case .noLegacyDBFound:
                // Fresh install or post-v1.3.0 user: bundle shipped
                // per-source DBs directly; no migration needed.
                return
            case let .alreadyMigrated(legacyFile, splitFiles):
                let legacyName = legacyFile.lastPathComponent
                let perSourceCount = splitFiles.count
                logger.info("✅ Per-source DB split already complete: legacy \(legacyName) is a stale leftover.")
                logger.info("   \(perSourceCount) per-source DB(s) live. Safe to delete the legacy file manually.")
                return
            case let .legacyFileMalformed(legacyFile, reason):
                logger.warning(
                    "⚠️  Legacy \(legacyFile.lastPathComponent) found but schema is malformed (\(reason)); skipping migration. Re-run `cupertino setup` after manual cleanup."
                )
                return
            case let .migrationNeeded(legacyFile):
                logger.info("🔀 Per-source DB split migration needed: splitting \(legacyFile.lastPathComponent) into per-source DBs...")
                let reader = LiveLegacyDBReader(legacyFile: legacyFile)
                let writerFactory = LivePerDBWriterFactory.make(logger: logger)
                do {
                    let outcome = try await Distribution.PerSourceDBSplitMigrator.migrate(
                        legacyFile: legacyFile,
                        baseDirectory: baseDirectory,
                        registry: registry,
                        reader: reader,
                        writerFactory: writerFactory
                    )
                    for result in outcome.results {
                        let mb = Double(result.bytesWritten) / 1048576
                        logger.info(
                            String(
                                format: "  [%@] split: %d rows → %@ (%.1f MB)",
                                result.sourceID,
                                result.rowsWritten,
                                result.destinationDBPath.lastPathComponent,
                                mb
                            )
                        )
                    }
                    if let target = outcome.actualLegacyRenameTarget {
                        logger.info("📦 Legacy file preserved at \(target.lastPathComponent) for one release.")
                    }
                } catch {
                    logger.warning("⚠️  Per-source DB split migration failed: \(error). Legacy \(legacyFile.lastPathComponent) preserved; re-run `cupertino setup` to retry.")
                }
            }
        }

        // MARK: - #1037 legacy samples.db filename migration

        /// Detects a leftover pre-#1037 `samples.db` on disk and renames
        /// it to `apple-sample-code.db` so the post-#1037 readers find
        /// it. No-ops in every case except the one transition shape:
        ///   - both files exist: legacy is a stale leftover. Log a
        ///     warning and leave both in place (user manually deletes
        ///     after verifying the new file is intact).
        ///   - only the new file exists: fresh install on a post-#1037
        ///     bundle, nothing to do.
        ///   - only the legacy file exists: pre-#1037 user upgrading
        ///     across the rename. Rename in place; the
        ///     `samples_schema_version` table is created on the next
        ///     `Sample.Index.Database` open (the schema-version
        ///     fallback path from commit `ce4605d` handles the
        ///     PRAGMA-based version stamp seamlessly).
        ///   - neither exists: nothing to do.
        ///
        /// Best-effort: any FileManager error is logged as a warning
        /// and the helper returns. The legacy file stays in place so
        /// the user can inspect / re-run later. This is a UX nicety
        /// for the upgrade path, not a correctness gate.
        static func migrateLegacySamplesDatabaseIfNeeded(
            baseDirectory: URL,
            logger: any LoggingModels.Logging.Recording
        ) {
            let legacyPath = Sample.Index.legacySamplesDatabasePath(baseDirectory: baseDirectory)
            let currentPath = Sample.Index.databasePath(baseDirectory: baseDirectory)
            let fm = FileManager.default
            let legacyExists = fm.fileExists(atPath: legacyPath.path)
            let currentExists = fm.fileExists(atPath: currentPath.path)

            switch (legacyExists, currentExists) {
            case (false, _):
                // Steady state or fresh install: nothing to migrate.
                return
            case (true, true):
                logger.warning(
                    "⚠️  Both \(legacyPath.lastPathComponent) and \(currentPath.lastPathComponent) exist. " +
                        "The legacy filename is no longer read by cupertino post-#1037. " +
                        "Verify \(currentPath.lastPathComponent) is intact, then `rm \(legacyPath.path)` to clean up."
                )
                return
            case (true, false):
                do {
                    try fm.moveItem(at: legacyPath, to: currentPath)
                    // Critic round-6 finding #2: SQLite WAL/SHM sidecars
                    // are independent files (samples.db-wal /
                    // samples.db-shm). Renaming only samples.db leaves
                    // the sidecars stranded at the old path; SQLite's
                    // next open of apple-sample-code.db looks for
                    // apple-sample-code.db-wal and finds nothing,
                    // losing any un-checkpointed transactions from a
                    // crashed prior `cupertino save --source samples`. Move
                    // the sidecars too. Both naming forms (with and
                    // without the .db suffix) covered defensively.
                    for suffix in ["-wal", "-shm"] {
                        let legacySidecar = URL(fileURLWithPath: legacyPath.path + suffix)
                        guard fm.fileExists(atPath: legacySidecar.path) else { continue }
                        let currentSidecar = URL(fileURLWithPath: currentPath.path + suffix)
                        do {
                            try fm.moveItem(at: legacySidecar, to: currentSidecar)
                        } catch {
                            logger.warning(
                                "⚠️  Renamed \(legacyPath.lastPathComponent) but could not move sidecar " +
                                    "\(legacySidecar.lastPathComponent): \(error). Un-checkpointed Sample.Index " +
                                    "transactions in that sidecar may be lost. Re-run `cupertino save --source samples` " +
                                    "to rebuild if `cupertino doctor` flags missing rows."
                            )
                        }
                    }
                    logger.info(
                        "📦 Migrated legacy \(legacyPath.lastPathComponent) → \(currentPath.lastPathComponent) (#1037 filename rename)."
                    )
                } catch {
                    logger.warning(
                        "⚠️  Could not rename \(legacyPath.lastPathComponent) → \(currentPath.lastPathComponent): \(error). " +
                            "Sample-code search will be empty until you re-run `cupertino save --source samples` " +
                            "or manually rename the file."
                    )
                }
            }
        }
    }
}

// MARK: - Progress renderer

/// Subscribes to `Distribution.SetupService.Event` and renders the
/// terminal UI: download progress bar, extract spinner, version banner,
/// final summary. Pulled into its own type so `Command.Setup.run` stays a
/// flat orchestration body.
private final class SetupRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var spinnerIndex = 0
    private let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let barWidth = 30
    private let clearLine = "\r\u{1B}[K"

    func handle(_ event: Distribution.SetupService.Event) {
        switch event {
        case .starting:
            break

        case .statusResolved(let status):
            printPriorStatus(status)

        case .dbBackedUp(let filename, _, let backupURL):
            Cupertino.Context.composition.logging.recording.info(
                "💾 Backed up \(filename) → \(backupURL.lastPathComponent)"
            )

        case .downloadStart(let label):
            Cupertino.Context.composition.logging.recording.info("⬇️  Downloading \(label)...")

        case .downloadProgress(_, let progress):
            renderProgress(progress: progress)

        case .downloadComplete(let label, let bytes):
            printRaw("\n")
            let size = Shared.Utils.Formatting.formatBytes(bytes)
            Cupertino.Context.composition.logging.recording.info("   ✓ \(label) (\(size))")

        case .extractStart(let label):
            Cupertino.Context.composition.logging.recording.info("📂 Extracting \(label.lowercased())...")

        case .extractTick:
            renderExtractTick()

        case .extractComplete:
            printRaw("\(clearLine)")
            Cupertino.Context.composition.logging.recording.info("   ✓ Extracted")

        case .constraintsDownloadSkipped(let reason):
            Cupertino.Context.composition.logging.recording.warning(
                "Apple-constraints sidecar download failed: \(reason). Setup completed; "
                    + "`cupertino save` will run with iter-1+2 enrichment only (~16% constraint coverage). "
                    + "Re-run `cupertino setup` once network resolves, or run "
                    + "`cupertino-constraints-gen` locally to produce the file."
            )

        case .finished:
            break
        }
    }

    func printFinalSummary(outcome: Distribution.SetupService.Outcome) {
        Cupertino.Context.composition.logging.recording.output("")
        if outcome.skippedDownload {
            Cupertino.Context.composition.logging.recording.info("✅ Databases already exist (keeping them, per --keep-existing)")
        } else {
            Cupertino.Context.composition.logging.recording.info("✅ Setup complete!")
        }
        // #248 second cut: iterate the descriptor-driven placement list
        // instead of addressing 3 fixed outcome fields. Adding a 4th DB
        // no longer touches this renderer; the descriptor's displayName
        // drives the label and the list's construction order in
        // SetupService.run drives the print order. Label is right-padded
        // to 15 chars (including the trailing colon) to preserve the
        // historical column alignment exactly: "Documentation: ",
        // "Sample code:   ", "Packages:      ", "Version:       ".
        for placement in outcome.databases {
            let label = "\(placement.descriptor.displayName):".padding(toLength: 15, withPad: " ", startingAt: 0)
            Cupertino.Context.composition.logging.recording.info("   \(label)\(placement.path.path)")
        }
        Cupertino.Context.composition.logging.recording.info("   Version:       \(outcome.docsVersionWritten)")
        Cupertino.Context.composition.logging.recording.info("\n💡 Start the server with: cupertino serve")
    }

    // MARK: - Rendering helpers

    private func renderProgress(progress: Distribution.ArtifactDownloader.Progress) {
        lock.lock()
        let frame = spinner[spinnerIndex % spinner.count]
        spinnerIndex += 1
        lock.unlock()

        let written = Shared.Utils.Formatting.formatBytes(progress.bytesWritten)

        if let total = progress.totalBytes, total > 0 {
            let frac = Double(progress.bytesWritten) / Double(total)
            let filled = Int(frac * Double(barWidth))
            let empty = barWidth - filled
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
            let percent = String(format: "%3.0f%%", frac * 100)
            let totalStr = Shared.Utils.Formatting.formatBytes(total)
            printRaw("\(clearLine)   \(frame) [\(bar)] \(percent) (\(written)/\(totalStr))")
        } else {
            printRaw("\(clearLine)   \(frame) Downloading... \(written)")
        }
    }

    private func renderExtractTick() {
        lock.lock()
        let frame = spinner[spinnerIndex % spinner.count]
        spinnerIndex += 1
        lock.unlock()
        printRaw("\(clearLine)   \(frame) Extracting databases...")
    }

    private func printRaw(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        fflush(stdout)
    }

    private func printPriorStatus(_ status: Distribution.InstalledVersion.Status) {
        switch status {
        case .missing:
            return
        case .current(let version):
            Cupertino.Context.composition.logging.recording.info(
                "ℹ️  Currently installed: v\(version) (same as the binary's expected version)."
            )
            Cupertino.Context.composition.logging.recording.info(
                "   Re-downloading v\(version). This is a refresh, not an upgrade."
            )
            Cupertino.Context.composition.logging.recording.info("   Tip: pass --keep-existing to skip this download.\n")
        case .stale(let installed, let current):
            Cupertino.Context.composition.logging.recording.info("⬆️  Upgrading databases: v\(installed) → v\(current).\n")
        case .unknown(let current):
            Cupertino.Context.composition.logging.recording.info("ℹ️  Databases exist but their version is unknown (legacy install).")
            Cupertino.Context.composition.logging.recording.info("   Downloading v\(current) and stamping the version file.\n")
        }
    }
}
