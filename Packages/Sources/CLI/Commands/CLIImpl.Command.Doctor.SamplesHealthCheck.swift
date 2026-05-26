import Diagnostics
import DistributionModels
import Foundation
import LoggingModels
import SharedConstants

extension CLIImpl.Command.Doctor {
    /// `Distribution.DatabaseHealthCheck` conformer for the sample-code
    /// index database. Warning-only: a missing or empty samples index
    /// emits a warning line but does not fail the overall doctor
    /// verdict; the server runs without the sample-code search just
    /// unavailable. Always returns `true`.
    ///
    /// **#1037 label**: the descriptor is `.appleSampleCode` (filename
    /// `apple-sample-code.db`); the section header reflects that
    /// filename so the operator sees what's actually on disk. Pre-#1037
    /// the descriptor was `.samples` (filename `samples.db`); the
    /// rename is documented at `Shared.Models.DatabaseDescriptor.appleSampleCode`.
    struct SamplesHealthCheck: Distribution.DatabaseHealthCheck {
        let descriptor: Shared.Models.DatabaseDescriptor = .appleSampleCode
        let isRequired: Bool = false

        let samplesDBURL: URL

        init(samplesDBURL: URL) {
            self.samplesDBURL = samplesDBURL
        }

        func run(output recording: any Logging.Recording) async -> Bool {
            recording.output("🧪 Sample Code Index (\(descriptor.filename))")

            guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
                recording.output("   ⚠  Database: \(samplesDBURL.path) (not found)")
                recording.output("     → Run: cupertino fetch --source samples && cupertino cleanup && cupertino save --source samples")
                recording.output("")
                return true
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: samplesDBURL.path)[.size] as? UInt64) ?? 0
            recording.output("   ✓ Database: \(samplesDBURL.path)")
            recording.output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            let projectCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "projects"))
            let fileCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "files"))
            let symbolCount = Diagnostics.Probes.rowCount(at: samplesDBURL, sql: Shared.Utils.SQL.countRows(in: "file_symbols"))
            if let projectCount { recording.output("   ✓ Projects: \(projectCount)") }
            if let fileCount { recording.output("   ✓ Indexed files: \(fileCount)") }
            if let symbolCount { recording.output("   ✓ Indexed symbols: \(symbolCount)") }
            recording.output("")
            return true
        }
    }
}
