@testable import Core
import Foundation
import Testing
import TestSupport
@testable import TUI

// MARK: - PackageEntry Tests

@Test("PackageEntry initializes with package data")
func packageEntryInitialization() {
    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift",
        url: "https://github.com/apple/swift",
        description: "The Swift Programming Language",
        stars: 65000,
        language: "C++",
        license: "Apache-2.0",
        fork: false,
        archived: false,
        updatedAt: "2025-11-19"
    )

    let entry = PackageEntry(package: pkg, isSelected: false, isDownloaded: true)

    #expect(entry.package.owner == "apple", "Should store package owner")
    #expect(entry.package.repo == "swift", "Should store package repo")
    #expect(!entry.isSelected, "Should not be selected")
    #expect(entry.isDownloaded, "Should be marked as downloaded")
}

@Test("PackageEntry isSelected can be toggled")
func packageEntrySelection() {
    let pkg = SwiftPackageEntry(
        owner: "vapor",
        repo: "vapor",
        url: "https://github.com/vapor/vapor",
        description: "A server-side Swift framework",
        stars: 24000,
        language: "Swift",
        license: "MIT",
        fork: false,
        archived: false,
        updatedAt: "2025-11-18"
    )

    var entry = PackageEntry(package: pkg, isSelected: false, isDownloaded: false)

    #expect(!entry.isSelected, "Should start unselected")

    entry.isSelected = true
    #expect(entry.isSelected, "Should be selected after toggling")

    entry.isSelected = false
    #expect(!entry.isSelected, "Should be unselected after toggling again")
}

@Test("PackageEntry isDownloaded reflects local state")
func packageEntryDownloadStatus() {
    let pkg = SwiftPackageEntry(
        owner: "realm",
        repo: "SwiftLint",
        url: "https://github.com/realm/SwiftLint",
        description: "A tool to enforce Swift style",
        stars: 18000,
        language: "Swift",
        license: "MIT",
        fork: false,
        archived: false,
        updatedAt: "2025-11-17"
    )

    let notDownloaded = PackageEntry(package: pkg, isSelected: false, isDownloaded: false)
    #expect(!notDownloaded.isDownloaded, "Should not be marked as downloaded")

    let downloaded = PackageEntry(package: pkg, isSelected: false, isDownloaded: true)
    #expect(downloaded.isDownloaded, "Should be marked as downloaded")
}

@Test("PackageEntry works with different package data")
func packageEntryVariousData() {
    // Test with minimal data
    let minimalPkg = SwiftPackageEntry(
        owner: "user",
        repo: "repo",
        url: "https://github.com/user/repo",
        description: nil,
        stars: 0,
        language: nil,
        license: nil,
        fork: true,
        archived: true,
        updatedAt: nil
    )

    let minimalEntry = PackageEntry(package: minimalPkg, isSelected: false, isDownloaded: false)
    #expect(minimalEntry.package.owner == "user", "Should handle minimal data")
    #expect(minimalEntry.package.description == nil, "Should handle nil description")
    #expect(minimalEntry.package.fork, "Should handle fork status")
    #expect(minimalEntry.package.archived, "Should handle archived status")

    // Test with full data
    let fullPkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift-nio",
        url: "https://github.com/apple/swift-nio",
        description: "Event-driven network application framework",
        stars: 7500,
        language: "Swift",
        license: "Apache-2.0",
        fork: false,
        archived: false,
        updatedAt: "2025-11-19"
    )

    let fullEntry = PackageEntry(package: fullPkg, isSelected: true, isDownloaded: true)
    #expect(fullEntry.package.description != nil, "Should handle full data")
    #expect(fullEntry.package.license == "Apache-2.0", "Should store license")
    #expect(fullEntry.isSelected, "Should be selected")
    #expect(fullEntry.isDownloaded, "Should be downloaded")
}
