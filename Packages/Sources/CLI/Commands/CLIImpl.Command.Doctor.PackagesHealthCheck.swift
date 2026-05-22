import Diagnostics
import DistributionModels
import Foundation
import LoggingModels
import SharedConstants

extension CLIImpl.Command.Doctor {
    /// `Distribution.DatabaseHealthCheck` conformer for `packages.db`.
    /// Warning-only: a missing packages index emits a warning + the
    /// expected bundled version but does not fail the overall doctor
    /// verdict; the server runs without the packages tool. Renders
    /// the same section as the pre-#930 `Doctor.checkPackagesDatabase`
    /// private method, byte-for-byte. Schema version is reported via
    /// the bundle-wide `Shared.Constants.App.databaseVersion`
    /// constant rather than a PRAGMA because packages.db is
    /// downloaded as part of the v1.0+ bundle, not migrated. Always
    /// returns `true`.
    struct PackagesHealthCheck: Distribution.DatabaseHealthCheck {
        let descriptor: Shared.Models.DatabaseDescriptor = .packages
        let isRequired: Bool = false

        let packagesDBURL: URL

        init(packagesDBURL: URL) {
            self.packagesDBURL = packagesDBURL
        }

        func run(output recording: any Logging.Recording) async -> Bool {
            recording.output("📦 Packages Index (packages.db)")

            guard FileManager.default.fileExists(atPath: packagesDBURL.path) else {
                recording.output("   ⚠  Database: \(packagesDBURL.path) (not found)")
                recording.output("     → Run: cupertino setup  (downloads the pre-built packages index)")
                recording.output("     Expected version: \(Shared.Constants.App.databaseVersion)")
                recording.output("")
                return true
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: packagesDBURL.path)[.size] as? UInt64) ?? 0
            recording.output("   ✓ Database: \(packagesDBURL.path)")
            recording.output("   ✓ Size: \(Shared.Utils.Formatting.formatBytes(Int64(fileSize)))")

            let packageCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: Shared.Utils.SQL.countRows(in: "packages"))
            let fileCount = Diagnostics.Probes.rowCount(at: packagesDBURL, sql: Shared.Utils.SQL.countRows(in: "package_files"))
            if let packageCount { recording.output("   ✓ Packages: \(packageCount)") }
            if let fileCount { recording.output("   ✓ Indexed files: \(fileCount)") }
            recording.output("   ℹ  Bundled version: \(Shared.Constants.App.databaseVersion)")
            recording.output("")
            return true
        }
    }
}
