import ArgumentParser
import Cleanup
import Foundation
import Logging
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Cleanup Command

extension Command {
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
            help: "Sample code directory to clean (default: \(Shared.Constants.defaultSampleCodeDirectory.path))"
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
            let directory: URL
            if let customDir = sampleCodeDir {
                directory = URL(fileURLWithPath: customDir).expandingTildeInPath
            } else {
                directory = Shared.Constants.defaultSampleCodeDirectory
            }

            guard FileManager.default.fileExists(atPath: directory.path) else {
                Logging.Log.error("Sample code directory not found: \(directory.path)")
                Logging.Log.error("Run 'cupertino fetch --type code' first to download sample code.")
                throw ExitCode.failure
            }

            if dryRun {
                Logging.Log.output("🔍 Cupertino - Cleanup Dry Run")
                Logging.Log.output("")
                Logging.Log.output("   Directory: \(directory.path)")
                Logging.Log.output("   (No files will be modified)")
                Logging.Log.output("")
            } else {
                Logging.Log.output("🧹 Cupertino - Cleaning Sample Code Archives")
                Logging.Log.output("")
                Logging.Log.output("   Directory: \(directory.path)")
                if keepOriginals {
                    Logging.Log.output("   Mode: Keep originals (cleaned files saved as .cleaned.zip)")
                } else {
                    Logging.Log.output("   Mode: Replace originals")
                }
                Logging.Log.output("")
            }

            let cleaner = Sample.Cleanup.Cleaner(
                sampleCodeDirectory: directory,
                dryRun: dryRun,
                keepOriginals: keepOriginals
            )

            let stats = try await cleaner.cleanup { progress in
                let percent = String(format: "%.1f", progress.percentage)
                let saved = Shared.Utils.Formatting.formatBytes(progress.originalSize - progress.cleanedSize)
                Logging.Log.output("   [\(percent)%] \(progress.currentFile) (saved \(saved))")
            }

            Logging.Log.output("")

            if dryRun {
                Logging.Log.output("📊 Dry Run Summary:")
            } else {
                Logging.Log.output("✅ Cleanup completed!")
            }

            Logging.Log.output("   Total archives: \(stats.totalArchives)")
            Logging.Log.output("   Cleaned: \(stats.cleanedArchives)")
            Logging.Log.output("   Skipped (already clean): \(stats.skippedArchives)")
            Logging.Log.output("   Errors: \(stats.errors)")
            Logging.Log.output("   Items to remove: \(stats.totalItemsRemoved)")
            Logging.Log.output("")
            Logging.Log.output("   Original size: \(Shared.Utils.Formatting.formatBytes(stats.originalTotalSize))")
            if !dryRun {
                Logging.Log.output("   Cleaned size: \(Shared.Utils.Formatting.formatBytes(stats.cleanedTotalSize))")
                Logging.Log.output(
                    "   Space saved: \(Shared.Utils.Formatting.formatBytes(stats.spaceSaved)) " +
                        "(\(String(format: "%.1f", stats.spaceSavedPercentage))%)"
                )
            }

            if let duration = stats.duration {
                Logging.Log.output("   Duration: \(Int(duration))s")
            }
        }
    }
}
