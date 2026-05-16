import Foundation
import LoggingModels
@testable import Search
import SearchModels
import SQLite3
import Testing

// MARK: - #673 Phase E — typed schema-mismatch error

//
// Pre-fix the schema-mismatch path in `Search.Index.Migrations` threw
// `Search.Error.sqliteError(<long string>)`, which the CLI's
// `exit(withError:)` rendered as a generic failure (exit code 1) with
// the raw string. Callers (scripts, doctor, AI agents) had to parse the
// message text to detect the class of error.
//
// Post-fix `Search.Error.schemaVersionMismatch(currentDBVersion:
// expectedBinaryVersion:dbPath:)` carries the raw version numbers + DB
// path. The CLI top-level catches this case explicitly, prints the
// user-friendly `errorDescription`, and exits with `EX_DATAERR` (65)
// so scripts can detect the class without string parsing.
//
// These tests pin: (1) the migrator throws the typed case on each
// breaking-version boundary, (2) `errorDescription` includes the right
// remediation hint based on direction, (3) the parameters are wired
// straight through.

@Suite("#673 Phase E — schema-mismatch typed error", .serialized)
struct Issue673PhaseESchemaMismatchTests {
    // MARK: - Helpers

    /// Create a temp SQLite file stamped with the given user_version,
    /// no tables. The migrator opens this fresh and immediately hits
    /// the schema-mismatch branch.
    private func makeStampedDB(at url: URL, userVersion: Int) {
        var db: OpaquePointer?
        _ = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { sqlite3_close_v2(db) }
        _ = sqlite3_exec(db, "PRAGMA user_version = \(userVersion);", nil, nil, nil)
    }

    private func tempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-673-phase-e-\(UUID().uuidString).db")
    }

    // MARK: - Migrator throws typed error (forward direction: DB > binary)

    @Test("Future-version DB triggers .schemaVersionMismatch with raw version numbers + path")
    func futureVersionDBThrowsTypedError() async throws {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        makeStampedDB(at: dbURL, userVersion: 99) // Far-future version.

        do {
            _ = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
            Issue.record("expected .schemaVersionMismatch to throw; nothing was thrown")
        } catch let error as Search.Error {
            guard case .schemaVersionMismatch(let dbVersion, let binaryVersion, let path) = error else {
                Issue.record("expected .schemaVersionMismatch; got \(error)")
                return
            }
            #expect(dbVersion == 99)
            #expect(binaryVersion == Int(Search.Index.schemaVersion))
            #expect(path == dbURL.path)
        }
    }

    // MARK: - Migrator throws typed error (backward direction: DB < binary, breaking step)

    @Test(
        "Older-version DB at a breaking-step boundary throws .schemaVersionMismatch (not .sqliteError)",
        arguments: [4, 11, 12, 13, 14] // each of the explicit-throw boundaries in checkAndMigrateSchema
    )
    func olderVersionAtBreakingStepThrowsTypedError(staleVersion: Int) async throws {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        makeStampedDB(at: dbURL, userVersion: staleVersion)

        do {
            _ = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
            Issue.record("expected .schemaVersionMismatch to throw for v\(staleVersion); nothing was thrown")
        } catch let error as Search.Error {
            guard case .schemaVersionMismatch(let dbVersion, _, _) = error else {
                Issue.record("expected .schemaVersionMismatch for v\(staleVersion); got \(error)")
                return
            }
            #expect(dbVersion == staleVersion)
        }
    }

    // MARK: - errorDescription wording

    @Test("DB > binary → errorDescription recommends `brew upgrade cupertino`")
    func errorDescriptionRecommendsBrewUpgradeWhenDBIsNewer() {
        let error = Search.Error.schemaVersionMismatch(
            currentDBVersion: 99,
            expectedBinaryVersion: 15,
            dbPath: "/tmp/example.db"
        )
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("brew upgrade cupertino"), "expected brew-upgrade remediation; got: \(desc)")
        #expect(desc.contains("99"))
        #expect(desc.contains("15"))
        #expect(desc.contains("/tmp/example.db"))
        // Must NOT recommend the wrong remediation for this direction.
        #expect(
            desc.contains("cupertino setup") == false || desc.contains("force-reset"),
            "DB-newer case should not recommend `cupertino setup` as primary path; got: \(desc)"
        )
    }

    @Test("DB < binary → errorDescription recommends `cupertino setup`")
    func errorDescriptionRecommendsCupertinoSetupWhenDBIsOlder() {
        let error = Search.Error.schemaVersionMismatch(
            currentDBVersion: 13,
            expectedBinaryVersion: 15,
            dbPath: "/tmp/example.db"
        )
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("cupertino setup"), "expected cupertino-setup remediation; got: \(desc)")
        #expect(desc.contains("13"))
        #expect(desc.contains("15"))
        #expect(desc.contains("/tmp/example.db"))
        // Should also offer the rebuild-from-crawl alternative.
        #expect(desc.contains("cupertino save"), "expected cupertino-save alternative; got: \(desc)")
    }

    @Test("errorDescription includes no Swift stack-trace shapes")
    func errorDescriptionIsUserFriendly() {
        let error = Search.Error.schemaVersionMismatch(
            currentDBVersion: 99,
            expectedBinaryVersion: 15,
            dbPath: "/tmp/example.db"
        )
        let desc = error.errorDescription ?? ""
        // Defensive: anything that looks like a stack-trace marker would be wrong here.
        #expect(desc.contains("schemaVersionMismatch") == false, "errorDescription leaked the enum case name")
        #expect(desc.contains("file:///") == false, "errorDescription leaked a file:// URL")
        #expect(desc.contains(".swift") == false, "errorDescription leaked a Swift source file path")
    }

    // MARK: - Match-binary case is NOT a mismatch (smoke)

    @Test("Matching-version DB does NOT throw .schemaVersionMismatch (sanity)")
    func matchingVersionDBDoesNotMismatch() async throws {
        let dbURL = tempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL) }
        makeStampedDB(at: dbURL, userVersion: Int(Search.Index.schemaVersion))

        // Should open without throwing — the migrator returns immediately
        // because currentVersion == Self.schemaVersion at line 33.
        let index = try await Search.Index(dbPath: dbURL, logger: Logging.NoopRecording())
        await index.disconnect()
    }
}
