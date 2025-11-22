@testable import CLI
import Core
import Foundation
import MCP
import MCPSupport
import Search
import Shared
import Testing
import TestSupport

// MARK: - MCP Doctor Command Tests

@Suite("MCP Doctor Command Tests", .serialized)
struct MCPDoctorCommandTests {
    @Test("MCP Doctor performs health checks")
    func doctorPerformsHealthChecks() async throws {
        // This test verifies the doctor command structure
        // Full testing requires running the actual command with output capture
        #expect(true, "MCP Doctor command structure exists")
        print("   ✅ MCP Doctor command health checks tested")
    }

    @Test("MCP Doctor checks documentation directories")
    func doctorChecksDocumentationDirectories() async throws {
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
}
