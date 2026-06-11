import Foundation
import SearchModels
import SQLite3

public extension Search {
    final class Statement: @unchecked Sendable {
        private let stmt: OpaquePointer
        private let database: OpaquePointer

        init(stmt: OpaquePointer, database: OpaquePointer) {
            self.stmt = stmt
            self.database = database
        }

        deinit {
            sqlite3_finalize(stmt)
        }

        public func bind(index: Int32, _ value: String) throws {
            guard sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil) == SQLITE_OK else {
                throw Search.Error.sqliteError(errorMessage())
            }
        }

        public func bind(index: Int32, _ value: Int32) throws {
            guard sqlite3_bind_int(stmt, index, value) == SQLITE_OK else {
                throw Search.Error.sqliteError(errorMessage())
            }
        }

        public func bind(index: Int32, _ value: Int64) throws {
            guard sqlite3_bind_int64(stmt, index, value) == SQLITE_OK else {
                throw Search.Error.sqliteError(errorMessage())
            }
        }

        public func bindNull(index: Int32) throws {
            guard sqlite3_bind_null(stmt, index) == SQLITE_OK else {
                throw Search.Error.sqliteError(errorMessage())
            }
        }

        @discardableResult
        public func step() throws -> Bool {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                return true
            } else if rc == SQLITE_DONE {
                return false
            } else {
                throw Search.Error.sqliteError(errorMessage())
            }
        }

        public func columnText(index: Int32) -> String {
            if let cString = sqlite3_column_text(stmt, index) {
                return String(cString: cString)
            }
            return ""
        }

        public func columnTextOptional(index: Int32) -> String? {
            if let cString = sqlite3_column_text(stmt, index) {
                return String(cString: cString)
            }
            return nil
        }

        public func columnInt(index: Int32) -> Int32 {
            sqlite3_column_int(stmt, index)
        }

        public func columnInt64(index: Int32) -> Int64 {
            sqlite3_column_int64(stmt, index)
        }

        public func columnDouble(index: Int32) -> Double {
            sqlite3_column_double(stmt, index)
        }

        private func errorMessage() -> String {
            String(cString: sqlite3_errmsg(database))
        }
    }
}
