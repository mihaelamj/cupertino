import Foundation
import SQLite3
import SQLiteSupport

// MARK: - CupertinoDataEngine.SchemaProbe

extension CupertinoDataEngine {
    enum SchemaProbe {
        static func assertPragmaUserVersion(
            at url: URL,
            expected: Int32,
            role: String
        ) throws {
            let actual = try withReadOnlyConnection(at: url, role: role) { database in
                try readPragmaUserVersion(database: database, role: role, path: url.path)
            }
            guard actual == expected else {
                throw Error.schemaVersionMismatch(role: role, path: url.path, expected: expected, actual: actual)
            }
        }

        static func assertSamplesSchemaVersion(
            at url: URL,
            expected: Int32,
            role: String
        ) throws {
            let actual = try withReadOnlyConnection(at: url, role: role) { database in
                try readSamplesSchemaVersion(database: database, role: role, path: url.path)
            }
            guard actual == expected else {
                throw Error.schemaVersionMismatch(role: role, path: url.path, expected: expected, actual: actual)
            }
        }

        private static func withReadOnlyConnection<T>(
            at url: URL,
            role: String,
            body: (OpaquePointer) throws -> T
        ) throws -> T {
            let database: OpaquePointer
            do {
                database = try SQLiteSupport.openReadOnly(at: url)
            } catch {
                throw Error.schemaVersionUnavailable(role: role, path: url.path, message: String(describing: error))
            }
            defer { sqlite3_close(database) }
            return try body(database)
        }

        private static func readPragmaUserVersion(
            database: OpaquePointer,
            role: String,
            path: String
        ) throws -> Int32 {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW
            else {
                throw Error.schemaVersionUnavailable(
                    role: role,
                    path: path,
                    message: sqliteErrorMessage(database)
                )
            }
            return sqlite3_column_int(statement, 0)
        }

        private static func readSamplesSchemaVersion(
            database: OpaquePointer,
            role: String,
            path: String
        ) throws -> Int32 {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT version FROM samples_schema_version WHERE id = 1 LIMIT 1"
            let prepare = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            if prepare == SQLITE_OK {
                let step = sqlite3_step(statement)
                if step == SQLITE_ROW {
                    return sqlite3_column_int(statement, 0)
                }
                throw Error.schemaVersionUnavailable(
                    role: role,
                    path: path,
                    message: "samples_schema_version has no version row"
                )
            }

            let legacyVersion = try readPragmaUserVersion(database: database, role: role, path: path)
            guard legacyVersion > 0 else {
                throw Error.schemaVersionUnavailable(
                    role: role,
                    path: path,
                    message: "samples_schema_version table is missing and PRAGMA user_version is 0"
                )
            }
            return legacyVersion
        }

        private static func sqliteErrorMessage(_ database: OpaquePointer) -> String {
            String(cString: sqlite3_errmsg(database))
        }
    }
}
