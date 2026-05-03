import Foundation

extension Shared {
    /// Date-based schema version stamp for cupertino's local databases
    /// (search.db, packages.db, samples.db). #234.
    ///
    /// Format: `YYYYMMDDhhmm` — twelve digits, all UTC, fixed-width so
    /// lex-comparison is correct. Stored in each DB's `schema_meta`
    /// table as the canonical version string; SQLite's
    /// `PRAGMA user_version` (Int32-only) becomes a coarse fallback
    /// only and isn't authoritative.
    ///
    /// Example: `202605042240` = 2026-05-04 22:40 UTC.
    public enum SchemaVersion {
        /// Pack y/m/d/h/m components into the canonical `YYYYMMDDhhmm`
        /// string. No validation — caller is expected to pass
        /// canonical components.
        public static func make(
            year: Int,
            month: Int,
            day: Int,
            hour: Int,
            minute: Int
        ) -> String {
            String(
                format: "%04d%02d%02d%02d%02d",
                year, month, day, hour, minute
            )
        }

        /// Current UTC time as a `YYYYMMDDhhmm` string. Used at
        /// schema-bump landing time to label the new format.
        public static func now(date: Date = Date()) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            return make(
                year: parts.year ?? 1970,
                month: parts.month ?? 1,
                day: parts.day ?? 1,
                hour: parts.hour ?? 0,
                minute: parts.minute ?? 0
            )
        }

        /// Decoded form of a `YYYYMMDDhhmm` version string. Struct
        /// (instead of a 5-tuple) keeps the linter happy and the
        /// fields self-documenting at the call site.
        public struct Components: Sendable, Equatable {
            public let year: Int
            public let month: Int
            public let day: Int
            public let hour: Int
            public let minute: Int
        }

        /// Inverse of `make`. Returns nil for inputs that aren't 12
        /// digits or that decompose to non-canonical components.
        public static func components(from version: String) -> Components? {
            guard version.count == 12,
                  version.allSatisfy(\.isASCII),
                  Int(version) != nil
            else { return nil }
            let chars = Array(version)
            guard
                let year = Int(String(chars[0..<4])),
                let month = Int(String(chars[4..<6])),
                let day = Int(String(chars[6..<8])),
                let hour = Int(String(chars[8..<10])),
                let minute = Int(String(chars[10..<12]))
            else { return nil }
            guard
                year >= 1970, year <= 9999,
                (1...12).contains(month),
                (1...31).contains(day),
                (0...23).contains(hour),
                (0...59).contains(minute)
            else { return nil }
            return Components(year: year, month: month, day: day, hour: hour, minute: minute)
        }

        /// Coarse Int32 fallback — `YYYYMMDD` only, dropping the time.
        /// Used to seed `PRAGMA user_version` for the rare consumer
        /// that reads the pragma directly. Authoritative version
        /// lives in the DB's `schema_meta` table as the full
        /// 12-digit string. Fits Int32 through year 2147.
        public static func dateOnlyInt32(from version: String) -> Int32 {
            guard let parts = components(from: version) else { return 0 }
            return Int32(parts.year * 10000 + parts.month * 100 + parts.day)
        }

        /// ISO-8601 UTC timestamp for `schema_meta(key='version_iso',
        /// value=...)`. Second resolution, no fractional seconds.
        /// Sister format to `now()` for consumers that want a
        /// human-readable line in `cupertino doctor`.
        public static func iso8601Now(date: Date = Date()) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            return formatter.string(from: date)
        }
    }
}
