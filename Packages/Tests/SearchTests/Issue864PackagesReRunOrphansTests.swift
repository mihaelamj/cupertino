import Foundation
import LoggingModels
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
import SQLite3
import Testing

// MARK: - #864 — packages.db re-run accumulates orphan package_symbols rows

/// Pre-#864 fix, the `Search.PackageIndex` connection-open path did NOT
/// run `PRAGMA foreign_keys = ON`. SQLite ships with FK enforcement
/// OFF per connection, so the schema's declared `ON DELETE CASCADE`
/// relationships from `package_files` → `package_metadata` and
/// `package_symbols` → `package_files` never fired. A
/// `cupertino save --packages` re-run against an already-populated DB
/// then accumulated ~1.4M orphan `package_symbols` rows (the previous
/// run's symbols, dangling off file_ids the indexer's wipe path had
/// deleted but whose cascade never propagated).
///
/// Two regression checks pinned here:
///
/// 1. **PRAGMA introspection.** Open a fresh `Search.PackageIndex`,
///    query `currentForeignKeysMode()`; expect `1` (ON). If a future
///    edit removes the `PRAGMA foreign_keys = ON` line from
///    `openDatabase`, this test fails immediately without needing the
///    end-to-end save fixture.
///
/// 2. **CASCADE behaviour.** Seed `package_metadata` + `package_files`
///    + `package_symbols` rows via a raw SQLite connection that
///    ALSO enables `foreign_keys = ON`, then `DELETE FROM
///    package_metadata WHERE …` and verify the two-hop cascade
///    propagated to `package_symbols` (count drops to zero).
///    Independent of `Search.PackageIndex` so it can't be silently
///    broken by accidental changes to the actor's pragma sequence.
///
/// Born from the v1.2.0 PR-2 autopilot run that surfaced #864 on a
/// real 183-package dev build (`docs/handoff/autopilot-build-dev-dbs.md`).
@Suite("#864 — packages.db FK CASCADE fires on re-run", .serialized)
struct Issue864PackagesReRunOrphansTests {
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-864-pkg-rerun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Regression check 1: PRAGMA introspection on the actor

    @Test("Search.PackageIndex enables PRAGMA foreign_keys on every open")
    func foreignKeysEnabledOnActorConnection() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("packages.db")

        let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        defer { Task { await index.disconnect() } }

        let mode = await index.currentForeignKeysMode()
        #expect(mode == 1, "Expected PRAGMA foreign_keys = 1 (ON); got \(mode ?? -1). See #864.")
    }

    @Test("Re-opening the same packages.db keeps PRAGMA foreign_keys ON")
    func foreignKeysEnabledOnReOpen() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("packages.db")

        do {
            let first = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
            await first.disconnect()
        }
        let second = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
        defer { Task { await second.disconnect() } }

        let mode = await second.currentForeignKeysMode()
        #expect(mode == 1, "Re-open dropped PRAGMA foreign_keys; the open path must re-set per-connection. See #864.")
    }

    // MARK: - Regression check 2: CASCADE semantics over the schema

    /// Open the same DB file via a fresh raw SQLite connection (so the
    /// schema is the production one from `Search.PackageIndex`'s
    /// migration path), then assert the two-hop CASCADE delete works
    /// when `PRAGMA foreign_keys = ON` is set on the connection. This
    /// is the structural shape that fails pre-#864 fix when the
    /// indexer's own connection is used.
    @Test("DELETE on package_metadata cascades through package_files to package_symbols")
    func cascadeDeleteWipesAllDependentRows() async throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("packages.db")

        // Open via the indexer once so the schema lands.
        do {
            let index = try await Search.PackageIndex(dbPath: dbPath, logger: Logging.NoopRecording())
            await index.disconnect()
        }

        // Re-open with raw sqlite3 + FKs ON; seed + cascade + assert.
        var db: OpaquePointer?
        try #require(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil) == SQLITE_OK)

        // Seed: 1 package, 1 file, 2 symbols.
        let seedSQL = """
        INSERT INTO package_metadata (owner, repo, url, fetched_at, is_apple_official)
          VALUES ('beta', 'cascade-test', 'https://test', 0, 0);
        INSERT INTO package_files (package_id, relpath, kind, module, size_bytes, indexed_at)
          VALUES (last_insert_rowid(), 'Sources/Foo.swift', 'source', 'Mod', 100, 0);
        INSERT INTO package_symbols
          (file_id, name, kind, line, column, signature, is_async, is_throws,
           is_public, is_static, attributes, conformances, generic_params,
           generic_constraints, enrichment_version)
          VALUES (last_insert_rowid(), 'Foo', 'struct', 1, 1, 'struct Foo', 0, 0, 1, 0,
                  NULL, NULL, NULL, NULL, NULL);
        INSERT INTO package_symbols
          (file_id, name, kind, line, column, signature, is_async, is_throws,
           is_public, is_static, attributes, conformances, generic_params,
           generic_constraints, enrichment_version)
          VALUES ((SELECT id FROM package_files WHERE relpath = 'Sources/Foo.swift'),
                  'Bar', 'struct', 2, 1, 'struct Bar', 0, 0, 1, 0,
                  NULL, NULL, NULL, NULL, NULL);
        """
        try #require(sqlite3_exec(db, seedSQL, nil, nil, nil) == SQLITE_OK)

        // Pre-cascade sanity.
        #expect(try singletonInt(db: db, "SELECT COUNT(*) FROM package_metadata;") == 1)
        #expect(try singletonInt(db: db, "SELECT COUNT(*) FROM package_files;") == 1)
        #expect(try singletonInt(db: db, "SELECT COUNT(*) FROM package_symbols;") == 2)

        // The wipe step from the indexer's re-run path.
        try #require(sqlite3_exec(
            db,
            "DELETE FROM package_metadata WHERE owner = 'beta' AND repo = 'cascade-test';",
            nil,
            nil,
            nil
        ) == SQLITE_OK)

        // Pre-#864 fix this leaves files + symbols behind. With FK ON
        // (the post-fix shape), both cascade through to zero.
        #expect(try singletonInt(db: db, "SELECT COUNT(*) FROM package_metadata;") == 0)
        #expect(
            try singletonInt(db: db, "SELECT COUNT(*) FROM package_files;") == 0,
            "package_files cascade-delete didn't fire. See #864."
        )
        #expect(
            try singletonInt(db: db, "SELECT COUNT(*) FROM package_symbols;") == 0,
            "package_symbols cascade-delete didn't fire. See #864."
        )

        // No orphan symbols either.
        let orphans = try singletonInt(db: db, """
        SELECT COUNT(*) FROM package_symbols ps
        LEFT JOIN package_files pf ON ps.file_id = pf.id
        WHERE pf.id IS NULL;
        """)
        #expect(orphans == 0)
    }

    // MARK: - Helpers

    private func singletonInt(db: OpaquePointer?, _ sql: String) throws -> Int {
        guard let db else { return -1 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }
}
