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
