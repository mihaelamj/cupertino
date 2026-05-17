import Foundation
import SQLite3

extension Diagnostics {
    /// Pure-data probes for cupertino's local databases and on-disk
    /// corpus directories. All read-only; safe to call against any DB
    /// (including locked ones — uses `SQLITE_OPEN_READONLY`).
    public enum Probes {
        // MARK: - SQLite probes

        /// Per-source row counts from `docs_metadata`. Returns an array
        /// of `(source, count)` tuples sorted by count descending.
        /// Empty when the table or DB can't be read.
        public static func perSourceCounts(at dbPath: URL) -> [(source: String, count: Int)] {
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return []
            }
            defer { sqlite3_close(db) }

            let sql = "SELECT source, COUNT(*) FROM docs_metadata GROUP BY source ORDER BY 2 DESC;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return []
            }

            var result: [(source: String, count: Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let source = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "(null)"
                let count = Int(sqlite3_column_int(stmt, 1))
                result.append((source, count))
            }
            return result
        }

        /// Read `PRAGMA user_version` directly without opening the DB
        /// through `Search.Index` (whose init throws on incompatible
        /// versions). Returns nil for unreadable / unopenable files.
        public static func userVersion(at dbPath: URL) -> Int32? {
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_close(db) }

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int(stmt, 0)
        }

        /// Read `PRAGMA journal_mode` from a SQLite file using a
        /// read-only connection. Used by `cupertino doctor` to verify
        /// each local DB is in WAL mode (#236) — anything else (`delete`,
        /// `truncate`, `persist`, `memory`, `off`) is a red flag that
        /// the init code didn't switch the file.
        ///
        /// `journal_mode` is the one SQLite PRAGMA that is **persistent
        /// in the file header**, so a fresh read-only connection
        /// reflects the writer's setting. `synchronous` and
        /// `journal_size_limit` are per-connection — they can't be
        /// probed this way and have no `Diagnostics.Probes.*` helpers.
        /// Their cross-process correctness is tested instead by
        /// querying through the writer actor's own connection.
        ///
        /// Returns the mode as a lowercase string (sqlite's own
        /// canonical form), or nil for unreadable / unopenable files.
        public static func journalMode(at dbPath: URL) -> String? {
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_close(db) }

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW,
                  let cString = sqlite3_column_text(stmt, 0)
            else {
                return nil
            }
            return String(cString: cString)
        }

        /// Run a `SELECT COUNT(*) ...` read-only against any sqlite DB.
        /// Returns nil on failure (most commonly because the table
        /// doesn't exist — surface that as blank rather than crash).
        public static func rowCount(at dbPath: URL, sql: String) -> Int? {
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_close(db) }

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return Int(sqlite3_column_int(stmt, 0))
        }

        /// #626 — kind histogram per `source` for `search.db`.
        /// Returns rows in the shape `(source, kind, count)` sorted by
        /// source ascending, count descending. Used by `cupertino
        /// doctor --kind-coverage` to surface the `unknown` rate and
        /// the dominant kinds per source — directly useful for
        /// verifying that indexer-side kind-extraction fixes (#615 /
        /// #633 / #664) actually moved the needle on the corpus.
        ///
        /// Joins `docs_metadata` (carries `source`) with `docs_structured`
        /// (carries the `kind` column added at schema v11 via #192 C).
        /// Rows where `docs_structured` has no entry contribute a
        /// synthetic `kind=NULL` bucket; the caller renders that as
        /// `(missing)` so it stays distinguishable from rows that
        /// successfully resolved to `kind=unknown`.
        ///
        /// Returns `nil` on any SQLite failure (DB locked, schema
        /// mismatch refused at open, file missing). The caller is
        /// expected to surface that as `(skipped)` rather than crash.
        public static func kindHistogramBySource(at dbPath: URL) -> [(source: String, kind: String, count: Int)]? {
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_close(db) }

            // COALESCE(s.kind, '(missing)') so rows with no docs_structured
            // entry render distinguishably from rows tagged `unknown`.
            let sql = """
            SELECT m.source,
                   COALESCE(s.kind, '(missing)') AS kind,
                   COUNT(*) AS n
            FROM docs_metadata m
            LEFT JOIN docs_structured s ON s.uri = m.uri
            GROUP BY m.source, COALESCE(s.kind, '(missing)')
            ORDER BY m.source ASC, n DESC;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }

            var rows: [(source: String, kind: String, count: Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let source = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let kind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "(missing)"
                let count = Int(sqlite3_column_int(stmt, 2))
                rows.append((source: source, kind: kind, count: count))
            }
            return rows
        }

        // MARK: - #275 — freshness / drift signal

        /// Per-source freshness report based on `docs_metadata.last_crawled`
        /// (Unix epoch seconds). Per the #275 spec, brew-installed users
        /// have no `cupertino-docs-private` checkout, so neither `git log`
        /// nor filesystem mtimes give them a useful answer to "how stale
        /// is my local index?". `last_crawled` is on every row and is
        /// stamped at indexer save time, so it's the authoritative signal
        /// available without external state.
        ///
        /// Returns per-source quantiles + total row count. Caller (doctor)
        /// renders timestamps as human-readable dates. Pure read; no
        /// writes; idempotent.
        ///
        /// Quantile choice: `oldest` / `p50` / `p90` / `newest` mirrors the
        /// pattern from the #275 spec's open question 1 (snapshot vs
        /// distribution): a single snapshot timestamp hides per-page
        /// staleness when a long crawl spans days, while raw min/max
        /// can lie about the bulk. p50 + p90 surfaces both the typical
        /// age and the tail.
        ///
        /// Returns `nil` on any SQLite failure (DB locked, schema mismatch
        /// at open, file missing). The caller surfaces that as
        /// `(skipped)` rather than crash.
        public static func freshnessBySource(
            at dbPath: URL
        ) -> [FreshnessRow]? {
            var db: OpaquePointer?
            guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_close(db) }

            // Per-source min/max + count. SQLite has no native PERCENTILE_CONT,
            // so the p50 / p90 quantiles are computed in Swift after reading
            // all `(source, last_crawled)` pairs sorted ascending. For a
            // ~285k-row corpus that's ~2 MB of in-memory Int64s — well
            // within budget for a read-only doctor probe that runs once.
            let sql = """
            SELECT source, last_crawled
            FROM docs_metadata
            WHERE last_crawled > 0
            ORDER BY source ASC, last_crawled ASC;
            """

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }

            var bySource: [String: [Int64]] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let source = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let crawled = sqlite3_column_int64(stmt, 1)
                bySource[source, default: []].append(crawled)
            }

            return bySource
                .map { source, timestamps in
                    FreshnessRow(
                        source: source,
                        count: timestamps.count,
                        oldest: timestamps.first ?? 0,
                        p50: Self.quantile(sortedTimestamps: timestamps, fraction: 0.50),
                        p90: Self.quantile(sortedTimestamps: timestamps, fraction: 0.90),
                        newest: timestamps.last ?? 0
                    )
                }
                .sorted { $0.source < $1.source }
        }

        /// Nearest-rank quantile on a pre-sorted (ascending) Int64 array.
        /// Returns 0 on empty input; nearest-rank avoids the interpolation
        /// ambiguity that bites Postgres' `percentile_cont` vs `percentile_disc`
        /// and matches what humans expect ("the p90 is one of the actual
        /// observations, not a synthetic average").
        private static func quantile(sortedTimestamps: [Int64], fraction: Double) -> Int64 {
            guard !sortedTimestamps.isEmpty else { return 0 }
            let rank = Int((Double(sortedTimestamps.count) * fraction).rounded(.up)) - 1
            let clamped = max(0, min(sortedTimestamps.count - 1, rank))
            return sortedTimestamps[clamped]
        }

        /// Per-source row in the freshness report. Unix epoch seconds for
        /// every timestamp; caller renders to human-readable dates.
        public struct FreshnessRow: Sendable, Equatable {
            public let source: String
            public let count: Int
            public let oldest: Int64
            public let p50: Int64
            public let p90: Int64
            public let newest: Int64

            public init(source: String, count: Int, oldest: Int64, p50: Int64, p90: Int64, newest: Int64) {
                self.source = source
                self.count = count
                self.oldest = oldest
                self.p50 = p50
                self.p90 = p90
                self.newest = newest
            }
        }

        // MARK: - #673 Phase F — disk usage

        /// Free / total bytes on the volume backing the given directory.
        /// Read via `FileManager.attributesOfFileSystem(forPath:)` which
        /// wraps `statfs(2)` on Darwin. Pure value — caller decides what
        /// to do with the numbers (e.g. refuse a write that won't fit).
        ///
        /// Returns nil if the FileManager attributes can't be read
        /// (path doesn't exist + can't be resolved to a parent volume,
        /// permission denied, etc.). Callers treat nil as "can't check
        /// — defer to user's judgement" rather than refuse the operation.
        ///
        /// The directory doesn't need to exist itself; we walk up to the
        /// nearest existing ancestor so the check works for "we're about
        /// to create ~/.cupertino-dev/" scenarios.
        public static func diskUsage(at directory: URL) -> DiskUsage? {
            // Walk up to the nearest existing ancestor. `attributesOfFileSystem`
            // requires a path that actually resolves to a mounted volume;
            // a non-existent `~/.cupertino-dev/` would fail.
            var probe = directory
            while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
                probe = probe.deletingLastPathComponent()
            }
            guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: probe.path) else {
                return nil
            }
            guard let totalNumber = attrs[.systemSize] as? NSNumber,
                  let freeNumber = attrs[.systemFreeSize] as? NSNumber
            else {
                return nil
            }
            return DiskUsage(
                totalBytes: totalNumber.int64Value,
                freeBytes: freeNumber.int64Value
            )
        }

        /// Free / total disk space on a volume.
        public struct DiskUsage: Sendable, Equatable {
            public let totalBytes: Int64
            public let freeBytes: Int64

            public init(totalBytes: Int64, freeBytes: Int64) {
                self.totalBytes = totalBytes
                self.freeBytes = freeBytes
            }

            /// Free space as a fraction of total (0.0 – 1.0). Returns 0
            /// when total is non-positive (defensive — shouldn't happen
            /// on a real volume).
            public var freeFraction: Double {
                guard totalBytes > 0 else { return 0 }
                return Double(freeBytes) / Double(totalBytes)
            }

            /// Used bytes (total − free).
            public var usedBytes: Int64 {
                max(0, totalBytes - freeBytes)
            }
        }

        // MARK: - File-system probes

        /// Count corpus document files under `directory`. Matches `.md`
        /// and `.json` because different sources save in different
        /// formats (docs writes JSON, evolution + HIG write markdown,
        /// Apple Archive mixes both).
        public static func countCorpusFiles(in directory: URL) -> Int {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }

            var count = 0
            for case let fileURL as URL in enumerator
                where fileURL.pathExtension == "md" || fileURL.pathExtension == "json" {
                count += 1
            }
            return count
        }

        /// Walk `<directory>/<owner>/<repo>/README.md` and return the
        /// canonical `owner/repo` set (lowercased). Used to diff
        /// against user-selected URLs by NAME so doctor can report
        /// true orphans (downloaded but no longer selected) and true
        /// gaps (selected but not downloaded).
        public static func packageREADMEKeys(in directory: URL) -> Set<String> {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var keys = Set<String>()
            for case let fileURL as URL in enumerator
                where fileURL.lastPathComponent.lowercased() == "readme.md" {
                let components = fileURL.pathComponents
                guard components.count >= 3 else { continue }
                let owner = components[components.count - 3].lowercased()
                let repo = components[components.count - 2].lowercased()
                keys.insert("\(owner)/\(repo)")
            }
            return keys
        }

        /// Parse `selected-packages.json` and return the URL set. Tolerates
        /// missing keys and returns an empty set so callers can treat
        /// "no file" and "empty file" identically.
        public static func userSelectedPackageURLs(from fileURL: URL) -> Set<String> {
            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tiers = json["tiers"] as? [String: Any]
            else {
                return []
            }

            var urls = Set<String>()
            for (_, tierValue) in tiers {
                if let tier = tierValue as? [String: Any],
                   let packages = tier["packages"] as? [[String: Any]] {
                    for pkg in packages {
                        if let url = pkg["url"] as? String {
                            urls.insert(url)
                        }
                    }
                }
            }
            return urls
        }

        // MARK: - URL helpers

        /// Extract the canonical `owner/repo` key from a GitHub URL. Returns
        /// nil for non-GitHub URLs so non-comparable sources don't enter
        /// the orphan/missing diff.
        public static func ownerRepoKey(forGitHubURL url: String) -> String? {
            guard let parsed = URL(string: url),
                  parsed.host?.contains("github.com") == true else { return nil }
            let components = parsed.path.split(separator: "/").map(String.init)
            guard components.count >= 2 else { return nil }
            let owner = components[0]
            var repo = components[1]
            if repo.hasSuffix(".git") {
                repo = String(repo.dropLast(4))
            }
            return "\(owner.lowercased())/\(repo.lowercased())"
        }
    }
}
