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

    /// Classify the install state given which DBs are present on disk and
    /// what the version stamp says. The set of databases the install is
    /// considered "complete" against is `required`; any member of
    /// `required` missing from `present` triggers `.missing`. Cupertino
    /// can grow a 4th DB by adding a descriptor to the caller's
    /// `required` set without touching this signature (#248).
    ///
    /// `required` MUST be non-empty: an install with zero required
    /// databases is structurally meaningless and would silently
    /// classify any baseDir (including an empty one) as
    /// `.unknown` or `.current` purely on the version-stamp value.
    public static func classify(
        present: Set<Shared.Models.DatabaseDescriptor>,
        required: Set<Shared.Models.DatabaseDescriptor>,
        installedVersion: String?,
        currentVersion: String
    ) -> Status {
        precondition(!required.isEmpty, "Distribution.InstalledVersion.classify requires at least one required database")
        guard required.isSubset(of: present) else { return .missing }
        guard let installed = installedVersion else { return .unknown(current: currentVersion) }
        if installed == currentVersion {
            return .current(version: currentVersion)
        }
        return .stale(installed: installed, current: currentVersion)
    }
}
