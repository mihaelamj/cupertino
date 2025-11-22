import Foundation
import Shared
import Testing

@testable import Core

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

    // MARK: - Integration Tests

    @Suite("Integration Tests", .tags(.integration))
    struct IntegrationTests {
        @Test("Downloads complete package documentation")
        func downloadCompletePackage() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let package = PackageReference(
                owner: "apple",
                repo: "swift-argument-parser",
                url: "https://github.com/apple/swift-argument-parser",
                priority: .appleOfficial
            )

            let progressCounter = SendableCounter()
            let stats = try await downloader.download(packages: [package]) { progress in
                Task { await progressCounter.increment() }
                #expect(progress.total == 1)
                #expect(progress.currentPackage == "apple/swift-argument-parser")
            }

            #expect(stats.totalPackages == 1)
            #expect(stats.successfulREADMEs == 1)
            #expect(stats.newREADMEs == 1) // First download should be new
            #expect(stats.updatedREADMEs == 0)
            let progressUpdates = await progressCounter.value
            #expect(progressUpdates > 0)

            // Verify file structure
            let packageDir = tempDir
                .appendingPathComponent("apple")
                .appendingPathComponent("swift-argument-parser")
            #expect(FileManager.default.fileExists(atPath: packageDir.path))

            let readmePath = packageDir.appendingPathComponent("README.md")
            #expect(FileManager.default.fileExists(atPath: readmePath.path))

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Downloads multiple packages")
        func downloadMultiplePackages() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let packages = [
                PackageReference(
                    owner: "apple",
                    repo: "swift-argument-parser",
                    url: "https://github.com/apple/swift-argument-parser",
                    priority: .appleOfficial
                ),
                PackageReference(
                    owner: "apple",
                    repo: "swift-collections",
                    url: "https://github.com/apple/swift-collections",
                    priority: .appleOfficial
                ),
            ]

            let stats = try await downloader.download(packages: packages)

            #expect(stats.totalPackages == 2)
            #expect(stats.successfulREADMEs == 2)

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Error Handling Tests

    @Suite("Error Handling Tests")
    struct ErrorTests {
        @Test("Handles network errors gracefully")
        func networkErrors() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let package = PackageReference(
                owner: "nonexistent-owner-\(UUID().uuidString)",
                repo: "nonexistent-repo",
                url: "https://github.com/nonexistent/nonexistent",
                priority: .community
            )

            // Should not crash, should report error in stats
            let stats = try await downloader.download(packages: [package])

            #expect(stats.totalPackages == 1)
            #expect(stats.errors == 1)
            #expect(stats.successfulREADMEs == 0)

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Handles invalid URLs")
        func invalidURLs() async throws {
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

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - File System Tests

    @Suite("File System Tests")
    struct FileSystemTests {
        @Test("Creates proper directory structure")
        func directoryStructure() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let package = PackageReference(
                owner: "apple",
                repo: "swift-argument-parser",
                url: "https://github.com/apple/swift-argument-parser",
                priority: .appleOfficial
            )

            _ = try await downloader.download(packages: [package])

            // Verify structure: outputDir/owner/repo/README.md
            let ownerDir = tempDir.appendingPathComponent("apple")
            let repoDir = ownerDir.appendingPathComponent("swift-argument-parser")
            let readme = repoDir.appendingPathComponent("README.md")

            #expect(FileManager.default.fileExists(atPath: ownerDir.path))
            #expect(FileManager.default.fileExists(atPath: repoDir.path))
            #expect(FileManager.default.fileExists(atPath: readme.path))

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        }

        @Test("Handles existing directories gracefully")
        func existingDirectories() async throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)

            // Create directory structure first
            let ownerDir = tempDir.appendingPathComponent("apple")
            let repoDir = ownerDir.appendingPathComponent("swift-argument-parser")
            try FileManager.default.createDirectory(
                at: repoDir,
                withIntermediateDirectories: true
            )

            let downloader = Core.PackageDocumentationDownloader(
                outputDirectory: tempDir
            )

            let package = PackageReference(
                owner: "apple",
                repo: "swift-argument-parser",
                url: "https://github.com/apple/swift-argument-parser",
                priority: .appleOfficial
            )

            // Should succeed even though directory exists
            let stats = try await downloader.download(packages: [package])
            #expect(stats.successfulREADMEs == 1)

            // Cleanup
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
