import ArgumentParser
import Cleanup
import Foundation
import Logging
import Shared

// MARK: - Cleanup Command

struct CleanupCommand: AsyncParsableCommand {
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
        help: "Sample code directory to clean (default: ~/.cupertino/sample-code)"
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
            Log.error("Sample code directory not found: \(directory.path)")
            Log.error("Run 'cupertino fetch --type code' first to download sample code.")
            throw ExitCode.failure
        }

        if dryRun {
            Log.output("🔍 Cupertino - Cleanup Dry Run")
            Log.output("")
            Log.output("   Directory: \(directory.path)")
            Log.output("   (No files will be modified)")
            Log.output("")
        } else {
            Log.output("🧹 Cupertino - Cleaning Sample Code Archives")
            Log.output("")
            Log.output("   Directory: \(directory.path)")
            if keepOriginals {
                Log.output("   Mode: Keep originals (cleaned files saved as .cleaned.zip)")
            } else {
                Log.output("   Mode: Replace originals")
            }
            Log.output("")
        }

        let cleaner = SampleCodeCleaner(
            sampleCodeDirectory: directory,
            dryRun: dryRun,
            keepOriginals: keepOriginals
        )

        let stats = try await cleaner.cleanup { progress in
            let percent = String(format: "%.1f", progress.percentage)
            let saved = Shared.Formatting.formatBytes(progress.originalSize - progress.cleanedSize)
            Log.output("   [\(percent)%] \(progress.currentFile) (saved \(saved))")
        }

        Log.output("")

        if dryRun {
            Log.output("📊 Dry Run Summary:")
        } else {
            Log.output("✅ Cleanup completed!")
        }

        Log.output("   Total archives: \(stats.totalArchives)")
        Log.output("   Cleaned: \(stats.cleanedArchives)")
        Log.output("   Skipped (already clean): \(stats.skippedArchives)")
        Log.output("   Errors: \(stats.errors)")
        Log.output("   Items to remove: \(stats.totalItemsRemoved)")
        Log.output("")
        Log.output("   Original size: \(Shared.Formatting.formatBytes(stats.originalTotalSize))")
        if !dryRun {
            Log.output("   Cleaned size: \(Shared.Formatting.formatBytes(stats.cleanedTotalSize))")
            Log.output(
                "   Space saved: \(Shared.Formatting.formatBytes(stats.spaceSaved)) " +
                    "(\(String(format: "%.1f", stats.spaceSavedPercentage))%)"
            )
        }

        if let duration = stats.duration {
            Log.output("   Duration: \(Int(duration))s")
        }
    }
}
