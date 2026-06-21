import Foundation
import SearchModels
import SQLite3

extension Search.Indexer {
    /// Clear all documents from the index.
    ///
    /// Wipes every docs-schema content table, not just the FTS. The
    /// `ON DELETE CASCADE` foreign keys from `docs_structured` /
    /// `doc_symbols` / `doc_code_examples` to `docs_metadata` do NOT
    /// fire here because `PRAGMA foreign_keys` is off on this
    /// connection, so deleting only `docs_metadata` leaves the
    /// rich-data tables fully populated. A `--clear` rebuild that
    /// emptied only `docs_fts` + `docs_metadata` left stale rows in
    /// `docs_structured` (search saw the fresh FTS, but list-frameworks
    /// and structured reads saw the old + new rows merged). Delete
    /// every table explicitly. (2026-06-21 hig.db junk-survival bug.)
    public func clearIndex() async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = """
        DELETE FROM docs_fts;
        DELETE FROM doc_symbols_fts;
        DELETE FROM doc_code_fts;
        DELETE FROM doc_code_examples;
        DELETE FROM doc_imports;
        DELETE FROM doc_symbols;
        DELETE FROM inheritance;
        DELETE FROM framework_aliases;
        DELETE FROM docs_structured;
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
