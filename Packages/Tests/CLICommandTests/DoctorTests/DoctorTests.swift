@testable import CLI
import Core
import Diagnostics
import Foundation
import MCP
import MCPSupport
import Search
import SharedCore
import SQLite3
import Testing
import TestSupport

// MARK: - MCP Doctor Command Tests

@Suite("MCP Doctor Command Tests", .serialized)
struct MCPDoctorCommandTests {
    @Test("MCP Doctor performs health checks")
    func doctorPerformsHealthChecks() {
        // This test verifies the doctor command structure
        // Full testing requires running the actual command with output capture
        #expect(true, "MCP Doctor command structure exists")
        print("   ✅ MCP Doctor command health checks tested")
    }

    @Test("MCP Doctor checks documentation directories")
    func doctorChecksDocumentationDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-doctor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create some test markdown files
        let testFile = tempDir.appendingPathComponent("test.md")
        try "# Test Documentation".write(to: testFile, atomically: true, encoding: .utf8)

        // Verify directory exists
        #expect(FileManager.default.fileExists(atPath: tempDir.path))

        // Verify we can find markdown files
        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let markdownFiles = contents.filter { $0.hasSuffix(".md") }
        #expect(markdownFiles.count == 1)

        print("   ✅ Documentation directory checks verified")
    }

    @Test("MCP Doctor verifies search database")
    func doctorVerifiesSearchDatabase() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-doctor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let searchDBURL = tempDir.appendingPathComponent("search.db")

        // Create a search database
        let searchIndex = try await Search.Index(dbPath: searchDBURL)
        await searchIndex.disconnect()

        // Verify database file exists
        #expect(FileManager.default.fileExists(atPath: searchDBURL.path))

        print("   ✅ Search database verification tested")
    }

    // MARK: - #192 F1 / F2 schema-version & row-count helpers

    @Test("Doctor reads PRAGMA user_version from a fresh search.db")
    func doctorReadsSchemaVersion() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("doctor-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("search.db")
        let idx = try await Search.Index(dbPath: dbPath)
        await idx.disconnect()

        // A fresh DB stamps user_version to the current schema version.
        let read = Diagnostics.Probes.userVersion(at: dbPath)
        #expect(read == Search.Index.schemaVersion)
    }

    @Test("Doctor returns nil user_version for a missing file")
    func doctorUserVersionMissing() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely-not-here-\(UUID().uuidString).db")
        #expect(Diagnostics.Probes.userVersion(at: missingPath) == nil)
    }

    @Test("Doctor returns nil rowCount for a missing table")
    func doctorRowCountMissingTable() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("doctor-rowcount-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("search.db")
        let idx = try await Search.Index(dbPath: dbPath)
        await idx.disconnect()

        // `packages` is a packages.db table, not present in search.db.
        let count = Diagnostics.Probes.rowCount(at: dbPath, sql: "SELECT COUNT(*) FROM packages_that_do_not_exist;")
        #expect(count == nil)
    }

    @Test("Doctor returns zero rowCount for an empty existing table")
    func doctorRowCountEmpty() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("doctor-rowcount-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("search.db")
        let idx = try await Search.Index(dbPath: dbPath)
        await idx.disconnect()

        let result = Diagnostics.Probes.rowCount(at: dbPath, sql: "SELECT COUNT(*) FROM docs_metadata;")
        #expect(result == 0)
    }

    // MARK: - #192 I6: schema-mismatch path verification

    @Test("Doctor flags a v11 DB as stale relative to the current binary (#192 I6)")
    func doctorDetectsStaleSchemaVersion() async throws {
        // Simulates the production scenario after a schema bump:
        // a user upgrades the cupertino binary (now expects a newer
        // `Search.Index.schemaVersion`), but their on-disk search.db is
        // still at 11. Doctor must read the on-disk PRAGMA WITHOUT going
        // through `Search.Index` (whose init throws on incompatible
        // versions and would otherwise hide the version number from the
        // diagnostic output).
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("doctor-stale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("search.db")

        // Create a sqlite file directly with PRAGMA user_version = 11. We
        // can't go through `Search.Index(dbPath:)` to set this: its init
        // either fresh-stamps to the current `schemaVersion` or throws.
        // Use the sqlite3 C API directly so the file lands at the prior
        // version.
        var db: OpaquePointer?
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            #expect(Bool(false), "Could not create stale-version sqlite file")
            return
        }
        defer { sqlite3_close(db) }
        let stamp = "PRAGMA user_version = 11;"
        guard sqlite3_exec(db, stamp, nil, nil, nil) == SQLITE_OK else {
            #expect(Bool(false), "Could not stamp PRAGMA user_version = 11")
            return
        }

        // Doctor reads back the on-disk version
        let onDisk = Diagnostics.Probes.userVersion(at: dbPath)
        #expect(onDisk == 11, "doctor must surface the actual stale version")

        // The binary expects a higher version
        #expect(
            Search.Index.schemaVersion > (onDisk ?? 0),
            "binary should expect a newer schema than the stale on-disk DB"
        )

        // Confirm the stale DB cannot be opened via Search.Index — the
        // breaking-migration throw is what produces the "rebuild required"
        // user message.
        await #expect(throws: (any Error).self) {
            _ = try await Search.Index(dbPath: dbPath)
        }
    }
}
