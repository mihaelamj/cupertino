import Foundation
import SharedConstants

// MARK: - Distribution.InstalledVersion — concrete file I/O + classifier
//
// The `Distribution.InstalledVersion` namespace + `Status` value enum
// live in the foundation-only `DistributionModels` seam target. This
// file extends the same enum with file-I/O helpers (`read` / `write`)
// and the pure `classify(...)` function.

extension Distribution.InstalledVersion {
    /// Read the installed-version stamp from `<baseDir>/.installed-version`.
    /// Returns nil when the file is absent or empty after trimming.
    public static func read(in baseDir: URL) -> String? {
        let url = baseDir.appendingPathComponent(Shared.Constants.FileName.setupVersionFile)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Write the stamp atomically. Throws on filesystem failure.
    public static func write(_ version: String, in baseDir: URL) throws {
        let url = baseDir.appendingPathComponent(Shared.Constants.FileName.setupVersionFile)
        try version.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Classify the install state given which DB files are present and
    /// what the stamp says. All three DBs (search, samples, packages)
    /// must exist for any non-`.missing` state — `cupertino setup`
    /// installs all three since the packages-overhaul, so a missing
    /// one means the install is incomplete and should be re-run.
    public static func classify(
        searchDBExists: Bool,
        samplesDBExists: Bool,
        packagesDBExists: Bool,
        installedVersion: String?,
        currentVersion: String
    ) -> Status {
        guard searchDBExists, samplesDBExists, packagesDBExists else { return .missing }
        guard let installed = installedVersion else { return .unknown(current: currentVersion) }
        if installed == currentVersion {
            return .current(version: currentVersion)
        }
        return .stale(installed: installed, current: currentVersion)
    }
}
