import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

/// Regression suite for [#1132](https://github.com/mihaelamj/cupertino/issues/1132).
///
/// `updateFrameworkSynonyms` used to be `UPDATE framework_aliases SET synonyms
/// = ? WHERE identifier = ?`, which silently no-opped whenever the alias row
/// did not already exist. On a corpus where the alias table held only a few
/// source-level rows, none of the 22 hand-curated synonyms (corenfc, bluetooth,
/// ...) ever attached, yet `SynonymsPass` reported `rowsAffected: 22` because it
/// counted loop iterations rather than actual writes. The fix makes the method
/// an upsert that returns the real change count.
@Suite("#1132 framework-synonym upsert", .serialized)
struct Issue1132SynonymsUpsertTests {
    private static func tempDB() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1132-synonyms-\(UUID().uuidString).db")
    }

    /// Reads (synonyms, display_name) for an identifier, or nil if no row.
    private static func aliasRow(at dbURL: URL, identifier: String) throws -> (synonyms: String?, displayName: String?)? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return nil }
        let sql = "SELECT synonyms, display_name FROM framework_aliases WHERE identifier = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, (identifier as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let syn = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        let disp = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
        return (syn, disp)
    }

    @Test("synonyms attach by creating the alias row when none pre-exists")
    func upsertCreatesRowAndAttachesSynonyms() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        // corebluetooth has no pre-existing alias row; the old UPDATE-only path
        // wrote nothing here.
        let written = try await idx.updateFrameworkSynonyms(identifier: "corebluetooth", synonyms: "bluetooth")
        await idx.disconnect()

        #expect(written == 1, "upsert should write exactly one row, got \(written)")
        let row = try Self.aliasRow(at: dbPath, identifier: "corebluetooth")
        #expect(row?.synonyms == "bluetooth", "synonyms should attach to the created row")
    }

    @Test("upsert updates synonyms on an existing row without clobbering its names")
    func upsertPreservesExistingNames() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        try await idx.registerFrameworkAlias(identifier: "corenfc", displayName: "Core NFC")
        let written = try await idx.updateFrameworkSynonyms(identifier: "corenfc", synonyms: "nfc")
        await idx.disconnect()

        #expect(written == 1)
        let row = try Self.aliasRow(at: dbPath, identifier: "corenfc")
        #expect(row?.synonyms == "nfc", "synonyms should update on the existing row")
        #expect(row?.displayName == "Core NFC", "ON CONFLICT must not clobber display_name")
    }

    @Test("SynonymsPass reports rows actually written, not the loop count")
    func passReportsHonestRowCount() async throws {
        let dbPath = Self.tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)

        var total = 0
        for entry in [("corenfc", "nfc"), ("corebluetooth", "bluetooth"), ("corelocation", "location")] {
            total += try await idx.updateFrameworkSynonyms(identifier: entry.0, synonyms: entry.1)
        }
        await idx.disconnect()

        #expect(total == 3, "three upserts should report three rows written, got \(total)")
    }
}
