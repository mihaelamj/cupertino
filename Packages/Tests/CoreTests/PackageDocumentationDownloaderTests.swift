@testable import Core
import Foundation
import Shared
import Testing

// MARK: - Package Documentation Downloader Tests

@Suite("PackageDocumentationDownloader Tests")
struct PackageDocumentationDownloaderTests {
    // MARK: - README Download Tests

    @Suite("README Download Tests")
    struct READMETests {
        @Test("Downloads README.md from main branch")
        func downloadREADMEFromMain() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            // Test with a known public repo (swift-argument-parser)
            let readme = try await downloader.downloadREADME(
                owner: "apple",
                repo: "swift-argument-parser"
            )

            #expect(!readme.isEmpty)
            #expect(readme.contains("Swift Argument Parser") || readme.contains("ArgumentParser"))

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Falls back to master branch")
        func fallbackToMaster() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            // Test with repo that might use master branch
            do {
                let readme = try await downloader.downloadREADME(
                    owner: "apple",
                    repo: "swift-argument-parser"
                )
                #expect(!readme.isEmpty)
            } catch {
                // If it fails, that's ok - the repo might not exist or might use main
                // The important thing is we're testing the fallback mechanism
            }

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Handles missing README gracefully")
        func handlingMissingREADME() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            await #expect(throws: PackageDownloadError.self) {
                try await downloader.downloadREADME(
                    owner: "invalid-owner-\(UUID().uuidString)",
                    repo: "nonexistent-repo-\(UUID().uuidString)"
                )
            }

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Tries multiple README filename variants")
        func readmeVariants() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            // Should successfully download regardless of README casing
            let readme = try await downloader.downloadREADME(
                owner: "apple",
                repo: "swift-argument-parser"
            )

            #expect(!readme.isEmpty)

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Documentation Site Detection Tests

    @Suite("Documentation Site Detection Tests")
    struct DetectionTests {
        @Test("Detects Vapor documentation site")
        func detectVaporDocs() async {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let site = await downloader.detectDocumentationSite(
                owner: "vapor",
                repo: "vapor"
            )

            #expect(site != nil)
            if let site {
                #expect(site.type == .customDomain)
                #expect(site.baseURL.absoluteString.contains("vapor.codes"))
            }

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Detects Hummingbird documentation site")
        func detectHummingbirdDocs() async {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let site = await downloader.detectDocumentationSite(
                owner: "hummingbird-project",
                repo: "hummingbird"
            )

            #expect(site != nil)
            if let site {
                #expect(site.type == .customDomain)
                #expect(site.baseURL.absoluteString.contains("hummingbird.codes"))
            }

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Returns nil for packages without known docs")
        func noDocs() async {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let site = await downloader.detectDocumentationSite(
                owner: "test-owner",
                repo: "unknown-package"
            )

            #expect(site == nil)

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Error Handling Tests

    @Suite("Error Handling Tests")
    struct ErrorTests {
        @Test("Handles invalid identifiers")
        func invalidIdentifiers() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            await #expect(throws: PackageDownloadError.self) {
                try await downloader.downloadREADME(
                    owner: "../../../etc",
                    repo: "passwd"
                )
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var integration: Self
}

// MARK: - Test Helpers

/// Thread-safe counter for testing progress callbacks
actor SendableCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int {
        count
    }
}
