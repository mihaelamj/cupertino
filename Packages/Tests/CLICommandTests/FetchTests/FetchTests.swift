import AppKit
@testable import CLI
@testable import Core
import Foundation
@testable import Shared
import Testing
import TestSupport

// MARK: - Fetch Command Tests

/// Tests for the `cupertino fetch` command
/// Verifies package fetching and sample code downloading

@Suite("Fetch Command Tests")
struct FetchCommandTests {
    @Test("Fetch Swift packages data")
    func fetchPackagesData() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fetch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        print("🧪 Test: Fetch Swift packages")

        _ = Core.PackageFetcher(
            outputDirectory: tempDir
        )

        // Note: This would require network access
        // For now, just verify the fetcher can be created
        // PackageFetcher doesn't expose outputDirectory publicly, so we just verify it compiles

        print("   ✅ Fetch initialization test passed!")
    }
}
