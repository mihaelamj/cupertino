import Foundation

extension Diagnostics {
    /// Render an `Int32` `PRAGMA user_version` as either a date-style
    /// or sequential string. Mirrors the dual-format transition #234
    /// anticipates: legacy DBs stamp a small sequential int (e.g. `5`),
    /// post-#234 DBs stamp a `YYYYMMDD` int (e.g. `20260504`).
    public enum SchemaVersion {
        /// Format the on-disk version. Returns `"(unset)"` for `0` /
        /// negative values, `"<n> (YYYY-MM-DD, date-style)"` for
        /// values that parse as a sane date, or `"<n> (sequential)"`
        /// for everything else.
        public static func format(_ version: Int32) -> String {
            guard version > 0 else { return "(unset)" }
            let intValue = Int(version)
            let day = intValue % 100
            let month = (intValue / 100) % 100
            let year = intValue / 10000
            if year >= 1970, year <= 9999,
               (1...12).contains(month),
               (1...31).contains(day) {
                return String(format: "%d (%04d-%02d-%02d, date-style)", version, year, month, day)
            }
            return "\(version) (sequential)"
        }
    }
}
