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
