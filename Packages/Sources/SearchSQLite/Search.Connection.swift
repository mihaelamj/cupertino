import Foundation
import LoggingModels
import SearchModels
import SQLite3
import SQLiteSupport

public extension Search {
    final class Connection: @unchecked Sendable {
        public private(set) var database: OpaquePointer?
        public let dbPath: URL
        public let readOnly: Bool
        private let logger: any LoggingModels.Logging.Recording
        public private(set) var isInitialized = false

        public init(
            dbPath: URL,
            logger: any LoggingModels.Logging.Recording,
            readOnly: Bool = false
        ) {
            self.dbPath = dbPath
            self.logger = logger
            self.readOnly = readOnly
        }

        public func connect() throws {
            if !readOnly {
                let directory = dbPath.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            try openDatabase()
            isInitialized = true
        }

        public func disconnect() {
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
        }

        public func prepare(_ sql: String) throws -> Statement {
            guard let database else {
                throw Search.Error.databaseNotInitialized
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else {
                let errMsg = String(cString: sqlite3_errmsg(database))
                throw Search.Error.sqliteError("Prepare failed: \(errMsg)")
            }
            guard let stmt else {
                throw Search.Error.sqliteError("sqlite3_prepare_v2 returned nil statement")
            }
            return Statement(stmt: stmt, database: database)
        }

        public func execute(_ sql: String) throws {
            guard let database else {
                throw Search.Error.databaseNotInitialized
            }
            var errorPointer: UnsafeMutablePointer<Int8>?
            guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
                let errMsg = errorPointer.flatMap { String(cString: $0) } ?? "unknown error"
                if let errorPointer { sqlite3_free(errorPointer) }
                throw Search.Error.sqliteError("Execute failed: \(errMsg)")
            }
        }

        public func currentSynchronousMode() -> Int32? {
            readIntegerPragma("PRAGMA synchronous;")
        }

        public func currentJournalSizeLimit() -> Int64? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, "PRAGMA journal_size_limit;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int64(stmt, 0)
        }

        private func readIntegerPragma(_ pragma: String) -> Int32? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, pragma, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int(stmt, 0)
        }

        private func openDatabase() throws {
            var dbPointer: OpaquePointer?

            if readOnly {
                database = try SQLiteSupport.openReadOnly(at: dbPath)
                return
            }

            guard sqlite3_open(dbPath.path, &dbPointer) == SQLITE_OK else {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                sqlite3_close(dbPointer)
                throw Search.Error.sqliteError("Failed to open database: \(errorMessage)")
            }

            sqlite3_busy_timeout(dbPointer, 5000)

            if sqlite3_exec(dbPointer, "PRAGMA journal_mode = WAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to enable WAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .search
                )
            }

            if sqlite3_exec(dbPointer, "PRAGMA synchronous = NORMAL", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set synchronous=NORMAL on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .search
                )
            }

            if sqlite3_exec(dbPointer, "PRAGMA journal_size_limit = 67108864", nil, nil, nil) != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
                logger.warning(
                    "Failed to set journal_size_limit on \(dbPath.lastPathComponent): \(errorMessage)",
                    category: .search
                )
            }

            database = dbPointer
        }
    }
}
