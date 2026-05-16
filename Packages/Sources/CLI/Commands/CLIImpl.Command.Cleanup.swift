import ArgumentParser
import Cleanup
import CleanupModels
import Foundation
import Logging
import LoggingModels
import SharedConstants
// MARK: - Cleanup Command

extension CLIImpl.Command {
    struct Cleanup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "cleanup",
            abstract: "Clean up downloaded sample code archives",
            discussion: """
            Removes unnecessary files from sample code ZIP archives to reduce disk space.

            Files removed:
            • .git folders (often 7+ MB each)
            • .DS_Store files
            • xcuserdata folders
            • DerivedData folders
            • Build artifacts
            • Pods folders
            • .swiftpm folders

            This can reduce storage from ~26GB to ~2-3GB for a full sample code download.
            """
        )

        @Option(
            name: .long,
            help: "Sample code directory to clean (defaults to the sample-code/ subdirectory of the resolved base directory — typically ~/.cupertino/sample-code, unless overridden by cupertino.config.json)"
        )
        var sampleCodeDir: String?

        @Flag(
            name: .long,
            help: "Dry run - show what would be cleaned without modifying files"
        )
        var dryRun: Bool = false

        @Flag(
            name: .long,
            help: "Keep original ZIP files (saves cleaned versions with .cleaned.zip suffix)"
        )
        var keepOriginals: Bool = false

        mutating func run() async throws {
            // Path-DI composition sub-root (#535): one `Shared.Paths`
            // constructed at the top of run(); explicit URLs to every
            // consumer below.
            let paths = Shared.Paths.live()
            let directory: URL
            if let customDir = sampleCodeDir {
                directory = URL(fileURLWithPath: customDir).expandingTildeInPath
            } else {
                directory = paths.sampleCodeDirectory
            }

            guard FileManager.default.fileExists(atPath: directory.path) else {
                Cupertino.Context.composition.logging.recording.error("Sample code directory not found: \(directory.path)")
                Cupertino.Context.composition.logging.recording.error("Run 'cupertino fetch --type code' first to download sample code.")
                throw ExitCode.failure
            }

            if dryRun {
                Cupertino.Context.composition.logging.recording.output("🔍 Cupertino - Cleanup Dry Run")
                Cupertino.Context.composition.logging.recording.output("")
                Cupertino.Context.composition.logging.recording.output("   Directory: \(directory.path)")
                Cupertino.Context.composition.logging.recording.output("   (No files will be modified)")
                Cupertino.Context.composition.logging.recording.output("")
            } else {
                Cupertino.Context.composition.logging.recording.output("🧹 Cupertino - Cleaning Sample Code Archives")
                Cupertino.Context.composition.logging.recording.output("")
                Cupertino.Context.composition.logging.recording.output("   Directory: \(directory.path)")
                if keepOriginals {
                    Cupertino.Context.composition.logging.recording.output("   Mode: Keep originals (cleaned files saved as .cleaned.zip)")
                } else {
                    Cupertino.Context.composition.logging.recording.output("   Mode: Replace originals")
                }
                Cupertino.Context.composition.logging.recording.output("")
            }

            let cleaner = Sample.Cleanup.Cleaner(
                sampleCodeDirectory: directory,
                dryRun: dryRun,
                keepOriginals: keepOriginals,
            logger: Cupertino.Context.composition.logging.recording
            )

            let stats = try await cleaner.cleanup(progress: CleanupProgressObserver(
                recording: Cupertino.Context.composition.logging.recording,
                dryRun: dryRun
            ))

            Cupertino.Context.composition.logging.recording.output("")

            if dryRun {
                Cupertino.Context.composition.logging.recording.output("📊 Dry Run Summary:")
            } else {
                Cupertino.Context.composition.logging.recording.output("✅ Cleanup completed!")
            }

            Cupertino.Context.composition.logging.recording.output("   Total archives: \(stats.totalArchives)")
            Cupertino.Context.composition.logging.recording.output("   Cleaned: \(stats.cleanedArchives)")
            Cupertino.Context.composition.logging.recording.output("   Skipped (already clean): \(stats.skippedArchives)")
            Cupertino.Context.composition.logging.recording.output("   Errors: \(stats.errors)")
            Cupertino.Context.composition.logging.recording.output("   Items to remove: \(stats.totalItemsRemoved)")
            Cupertino.Context.composition.logging.recording.output("")
            Cupertino.Context.composition.logging.recording.output("   Original size: \(Shared.Utils.Formatting.formatBytes(stats.originalTotalSize))")
            if !dryRun {
                Cupertino.Context.composition.logging.recording.output("   Cleaned size: \(Shared.Utils.Formatting.formatBytes(stats.cleanedTotalSize))")
                Cupertino.Context.composition.logging.recording.output(
                    "   Space saved: \(Shared.Utils.Formatting.formatBytes(stats.spaceSaved)) " +
                        "(\(String(format: "%.1f", stats.spaceSavedPercentage))%)"
                )
            }

            if let duration = stats.duration {
                Cupertino.Context.composition.logging.recording.output("   Duration: \(Int(duration))s")
            }
        }

        /// Closure-free observer for `Sample.Cleanup.Cleaner.cleanup`
        /// progress. Prints per-archive progress lines through the
        /// binary's recorder. Replaces the previous trailing-closure
        /// pattern at the call site.
        ///
        /// #646 — in dry-run mode the per-file print + flush dominated
        /// elapsed time on the 619-zip corpus (~50s of the observed
        /// ~60s), making the command look hung to anyone watching with
        /// a 30-second timeout. Real cleanup keeps the per-file output
        /// (the real work justifies it). Dry-run now emits at most one
        /// progress line per ~5% chunk (`max(1, total / 20)`) plus the
        /// first and last entries so the user still sees that the
        /// process started + finished. Corpora of 50 or fewer archives
        /// keep the per-entry verbose output — small enough that
        /// per-file flushing doesn't cause the hang signal.
        private struct CleanupProgressObserver: Sample.Cleanup.CleanerProgressObserving {
            let recording: any LoggingModels.Logging.Recording
            let dryRun: Bool

            func observe(progress: Shared.Models.CleanupProgress) {
                guard CLIImpl.Command.Cleanup.shouldEmitProgress(progress, dryRun: dryRun) else { return }
                let percent = String(format: "%.1f", progress.percentage)
                let saved = Shared.Utils.Formatting.formatBytes(progress.originalSize - progress.cleanedSize)
                recording.output("   [\(percent)%] \(progress.currentFile) (saved \(saved))")
            }
        }

        /// #646 — throttling rule for the dry-run progress emitter. Lifted
        /// to an internal static helper so the test target can pin the
        /// shape (boundary entries, sampling stride, small-batch full
        /// verbosity) without exercising the full `cleanup()` pipeline.
        /// Pure function; no side effects, no observer state.
        static func shouldEmitProgress(
            _ progress: Shared.Models.CleanupProgress,
            dryRun: Bool
        ) -> Bool {
            // Real cleanup keeps the per-file verbose log — the work
            // takes seconds per archive and the per-file output is
            // diagnostic rather than spammy.
            guard dryRun else { return true }
            // Small batches stay verbose: per-file output completes
            // quickly and the user gets the same UX as before.
            let throttleThreshold = 50
            if progress.total <= throttleThreshold { return true }
            // Always emit the first and last entries so the run has
            // a visible start + finish boundary.
            if progress.current == 1 || progress.current == progress.total { return true }
            // 20 buckets across the run → ~5% granularity. Bigger
            // corpora collapse harder; the per-archive zipinfo cost
            // (a few ms per zip) is what's actually doing useful
            // work, not the stdout flush.
            let stride = max(1, progress.total / 20)
            return progress.current.isMultiple(of: stride)
        }
    }
}
