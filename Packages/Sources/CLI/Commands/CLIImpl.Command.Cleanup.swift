import ArgumentParser
import Cleanup
import Foundation
import LoggingModels
import Logging
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
                Logging.LiveRecording().error("Sample code directory not found: \(directory.path)")
                Logging.LiveRecording().error("Run 'cupertino fetch --type code' first to download sample code.")
                throw ExitCode.failure
            }

            if dryRun {
                Logging.LiveRecording().output("🔍 Cupertino - Cleanup Dry Run")
                Logging.LiveRecording().output("")
                Logging.LiveRecording().output("   Directory: \(directory.path)")
                Logging.LiveRecording().output("   (No files will be modified)")
                Logging.LiveRecording().output("")
            } else {
                Logging.LiveRecording().output("🧹 Cupertino - Cleaning Sample Code Archives")
                Logging.LiveRecording().output("")
                Logging.LiveRecording().output("   Directory: \(directory.path)")
                if keepOriginals {
                    Logging.LiveRecording().output("   Mode: Keep originals (cleaned files saved as .cleaned.zip)")
                } else {
                    Logging.LiveRecording().output("   Mode: Replace originals")
                }
                Logging.LiveRecording().output("")
            }

            let cleaner = Sample.Cleanup.Cleaner(
                sampleCodeDirectory: directory,
                dryRun: dryRun,
                keepOriginals: keepOriginals,
            logger: Logging.LiveRecording()
            )

            let stats = try await cleaner.cleanup { progress in
                let percent = String(format: "%.1f", progress.percentage)
                let saved = Shared.Utils.Formatting.formatBytes(progress.originalSize - progress.cleanedSize)
                Logging.LiveRecording().output("   [\(percent)%] \(progress.currentFile) (saved \(saved))")
            }

            Logging.LiveRecording().output("")

            if dryRun {
                Logging.LiveRecording().output("📊 Dry Run Summary:")
            } else {
                Logging.LiveRecording().output("✅ Cleanup completed!")
            }

            Logging.LiveRecording().output("   Total archives: \(stats.totalArchives)")
            Logging.LiveRecording().output("   Cleaned: \(stats.cleanedArchives)")
            Logging.LiveRecording().output("   Skipped (already clean): \(stats.skippedArchives)")
            Logging.LiveRecording().output("   Errors: \(stats.errors)")
            Logging.LiveRecording().output("   Items to remove: \(stats.totalItemsRemoved)")
            Logging.LiveRecording().output("")
            Logging.LiveRecording().output("   Original size: \(Shared.Utils.Formatting.formatBytes(stats.originalTotalSize))")
            if !dryRun {
                Logging.LiveRecording().output("   Cleaned size: \(Shared.Utils.Formatting.formatBytes(stats.cleanedTotalSize))")
                Logging.LiveRecording().output(
                    "   Space saved: \(Shared.Utils.Formatting.formatBytes(stats.spaceSaved)) " +
                        "(\(String(format: "%.1f", stats.spaceSavedPercentage))%)"
                )
            }

            if let duration = stats.duration {
                Logging.LiveRecording().output("   Duration: \(Int(duration))s")
            }
        }
    }
}
