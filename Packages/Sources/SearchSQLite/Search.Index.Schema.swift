import Foundation
import SearchModels
import SearchSchema
import SQLite3

extension Search.Indexer {
    /// Create every table, view, FTS5 virtual table, and index in the
    /// canonical `search.db` schema. Idempotent: the script in
    /// `Search.Schema.createAllTablesSQL` uses `CREATE ... IF NOT EXISTS`
    /// throughout, so re-running against an already-initialised database
    /// is a no-op.
    ///
    /// The DDL itself lives in the foundation-only `SearchSchema` target
    /// (epic #893 child #898 sub-PR A). This method owns the executor:
    /// the actor's internal `database` handle + the `sqlite3_exec` call.
    func createTables() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(database, Search.Schema.createAllTablesSQL, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw Search.Error.sqliteError("Failed to create tables: \(errorMessage)")
        }
    }

    // MARK: - Package Indexing
}
