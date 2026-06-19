import Foundation
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #1279 — read-only packages.db open gates on schema version

/// Isolation of the #1279 bug: `Search.PackageQuery.init` opened the file
/// through the shared read-only path and returned with NO `user_version`
/// check, so a present but version-skewed `packages.db` (e.g. an old bundle
/// left in place after a binary upgrade) opened silently and served results
/// from a schema this binary does not understand. The query path is strictly
/// read-only (#1194) and cannot rebuild, so the only correct behaviour is to
/// fail loudly with an actionable remediation. A `user_version` of 0 is the
/// unstamped/fresh sentinel and is NOT a skew (`Issue1190` builds such a
/// fixture and must keep opening). These tests fail on the pre-#1279 init
/// (no throw) and pass once the gate is in place.
@Suite("#1279 — read-only packages.db schema gate")
struct Issue1279PackageQuerySchemaGateTests {
    /// Build a packages-shaped, rollback-mode DB with `user_version` stamped to
    /// `userVersion`. No sidecars, the on-disk shape of a shipped bundle DB.
    private func makePackagesDB(userVersion: Int32) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pkgq-1279-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("packages.db")

        var db: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
        let setup = """
        CREATE VIRTUAL TABLE package_files_fts USING fts5(
            package_id UNINDEXED, owner UNINDEXED, repo UNINDEXED, module UNINDEXED,
            relpath UNINDEXED, kind UNINDEXED, title, content, symbols,
            tokenize='porter unicode61'
        );
        INSERT INTO package_files_fts
            (package_id, owner, repo, module, relpath, kind, title, content, symbols)
        VALUES
            (1, 'apple', 'swift-log', 'Logging', 'Sources/Logging/Logging.swift',
             'source', 'Logging', 'public struct Logger', 'Logger');
        PRAGMA user_version = \(userVersion);
        """
        #expect(sqlite3_exec(db, setup, nil, nil, nil) == SQLITE_OK)
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_close(db)
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + sidecar)
        }
        return dbURL
    }

    @Test("an older-version packages.db throws an actionable setup mismatch")
    func olderVersionThrowsSetupRemediation() async throws {
        let dbURL = try makePackagesDB(userVersion: 4)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        do {
            _ = try await Search.PackageQuery(dbPath: dbURL)
            Issue.record("expected a schema mismatch throw")
        } catch let error as Search.PackageQueryError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("cupertino setup"))
            #expect(message.contains(dbURL.path))
            #expect(message.contains("4"))
            #expect(message.contains("5"))
        }
    }

    @Test("a newer-version packages.db throws an actionable upgrade mismatch")
    func newerVersionThrowsUpgradeRemediation() async throws {
        let dbURL = try makePackagesDB(userVersion: 99)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        do {
            _ = try await Search.PackageQuery(dbPath: dbURL)
            Issue.record("expected a schema mismatch throw")
        } catch let error as Search.PackageQueryError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("brew upgrade"))
            #expect(message.contains("99"))
        }
    }

    @Test("a matching-version packages.db opens and queries")
    func matchingVersionOpens() async throws {
        let dbURL = try makePackagesDB(userVersion: 5)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let query = try await Search.PackageQuery(dbPath: dbURL)
        let content = try await query.fileContent(
            owner: "apple", repo: "swift-log", relpath: "Sources/Logging/Logging.swift"
        )
        #expect(content == "public struct Logger")
        await query.disconnect()
    }

    @Test("an unstamped (user_version 0) packages.db is not treated as a skew")
    func unstampedVersionOpens() async throws {
        let dbURL = try makePackagesDB(userVersion: 0)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let query = try await Search.PackageQuery(dbPath: dbURL)
        await query.disconnect()
    }
}
