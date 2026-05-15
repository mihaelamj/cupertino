import Foundation

// MARK: - Distribution.InstalledVersion — Status enum (pure value type)

extension Distribution {
    /// Installed-version stamp helper namespace. The Status enum is a
    /// pure value type and lives here; the file-I/O helpers
    /// (`read(in:)`, `write(_:in:)`) and the classifier function
    /// (`classify(...)`) live in the `Distribution` producer target as
    /// extensions on this enum.
    public enum InstalledVersion {
        /// Status of the installed databases relative to a target
        /// version. Pure enum for direct unit testing.
        public enum Status: Equatable, Sendable {
            case missing
            case current(version: String)
            case stale(installed: String, current: String)
            /// DBs exist but no version file (legacy install).
            case unknown(current: String)
        }
    }
}
