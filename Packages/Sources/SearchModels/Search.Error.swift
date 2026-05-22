import Foundation

extension Search {
    public enum Error: Swift.Error, LocalizedError {
        case databaseNotInitialized
        case sqliteError(String)
        case prepareFailed(String)
        case insertFailed(String)
        case searchFailed(String)
        case invalidQuery(String)
        /// #673 Phase E typed schema-mismatch error replacing the
        /// generic `.sqliteError("Database schema version X; binary
        /// expects version Y. …")` cases that previously bubbled out
        /// of `Search.Index.Migrations.runMigrations`. Carrying the
        /// raw version numbers + DB path lets the CLI top-level
        /// (`Cupertino.main`) print a user-friendly remediation hint
        /// AND exit with `EX_DATAERR` (65) so scripts can detect the
        /// class without parsing a string.
        ///
        /// Direction matters:
        ///   - `currentDBVersion > expectedBinaryVersion` → binary is
        ///     stale; suggest `brew upgrade cupertino` (or rebuild
        ///     the binary in a dev setup).
        ///   - `currentDBVersion < expectedBinaryVersion` → DB is
        ///     stale; suggest `cupertino setup` to download a matching
        ///     pre-built bundle.
        ///
        /// The errorDescription wires both branches into a single
        /// user-visible sentence; the CLI's catch path adds the exit
        /// code + suppresses the Swift stack trace.
        case schemaVersionMismatch(currentDBVersion: Int, expectedBinaryVersion: Int, dbPath: String)

        public var errorDescription: String? {
            switch self {
            case .databaseNotInitialized:
                return "Search database has not been initialized. Run 'cupertino build-index' first."
            case .sqliteError(let msg):
                return "SQLite error: \(msg)"
            case .prepareFailed(let msg):
                return "Failed to prepare SQL statement: \(msg)"
            case .insertFailed(let msg):
                return "Failed to insert document: \(msg)"
            case .searchFailed(let msg):
                return "Search query failed: \(msg)"
            case .invalidQuery(let msg):
                return "Invalid search query: \(msg)"
            case .schemaVersionMismatch(let dbVersion, let binaryVersion, let dbPath):
                if dbVersion > binaryVersion {
                    // DB is newer than binary, installed cupertino can't read it.
                    return """
                    Database schema mismatch: search.db at \(dbPath) is at schema version \(dbVersion), \
                    but this cupertino binary only understands up to version \(binaryVersion).

                    Remediation:
                      \u{2022} If you installed via Homebrew: `brew upgrade cupertino`
                      \u{2022} If you build cupertino from source: rebuild your binary so it matches the bundle's schema
                      \u{2022} To force-reset to the binary's current schema: `rm '\(dbPath)' && cupertino setup`
                    """
                } else {
                    // DB is older than binary, common after `brew upgrade cupertino` without a bundle refresh.
                    return """
                    Database schema mismatch: search.db at \(dbPath) is at schema version \(dbVersion), \
                    but this cupertino binary expects version \(binaryVersion).

                    Remediation:
                      \u{2022} Download the matching pre-built bundle: `cupertino setup`
                      \u{2022} Or rebuild from a local crawl: `rm '\(dbPath)' && cupertino save`
                    """
                }
            }
        }
    }
}
