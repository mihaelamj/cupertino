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
                recording: Cupertino.Context.composition.logging.recording
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
        private struct CleanupProgressObserver: Sample.Cleanup.CleanerProgressObserving {
            let recording: any LoggingModels.Logging.Recording

            func observe(progress: Shared.Models.CleanupProgress) {
                let percent = String(format: "%.1f", progress.percentage)
                let saved = Shared.Utils.Formatting.formatBytes(progress.originalSize - progress.cleanedSize)
                recording.output("   [\(percent)%] \(progress.currentFile) (saved \(saved))")
            }
        }
    }
}
