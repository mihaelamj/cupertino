import ArgumentParser
import Distribution
import Foundation
import Logging
import LoggingModels
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
            abstract: "Download every cupertino database (search.db, samples.db, packages.db) in one go"
        )

        @Option(name: .long, help: "Base directory for databases")
        var baseDir: String?

        @Flag(name: .long, help: "Skip the download and keep whatever databases are already installed")
        var keepExisting: Bool = false

        mutating func run() async throws {
            Cupertino.Context.composition.logging.recording.info("📦 Cupertino Setup\n")

            // Path-DI composition sub-root (#535): construct once at the top
            // of run(), then thread explicit URLs into every consumer.
            let paths = Shared.Paths.live()
            let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? paths.baseDirectory

            let renderer = SetupRenderer()
            let request = Distribution.SetupService.Request(
                baseDir: baseURL,
                keepExisting: keepExisting
            )

            do {
                let outcome = try await Distribution.SetupService.run(request) { event in
                    renderer.handle(event)
                }
                renderer.printFinalSummary(outcome: outcome)
            } catch {
                Cupertino.Context.composition.logging.recording.error("❌ Setup failed: \(error)")
                throw ExitCode.failure
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
        Cupertino.Context.composition.logging.recording.info("   Documentation: \(outcome.searchDBPath.path)")
        Cupertino.Context.composition.logging.recording.info("   Sample code:   \(outcome.samplesDBPath.path)")
        Cupertino.Context.composition.logging.recording.info("   Packages:      \(outcome.packagesDBPath.path)")
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
