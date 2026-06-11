import Foundation
import SearchModels
import SQLite3

extension Search.Indexer {
    /// Clear all documents from the index
    public func clearIndex() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = """
        DELETE FROM docs_fts;
        DELETE FROM docs_metadata;
        """

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw Search.Error.sqliteError("Failed to clear index: \(errorMessage)")
        }
    }
}
