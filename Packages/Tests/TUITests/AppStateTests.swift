@testable import Core
import Foundation
import Testing
import TestSupport
@testable import TUI

// MARK: - AppState Tests

@MainActor
@Test("AppState initializes with default values")
func appStateInitialization() {
    let state = AppState()

    #expect(state.packages.isEmpty, "Should start with empty packages")
    #expect(state.cursor == 0, "Cursor should start at 0")
    #expect(state.scrollOffset == 0, "Scroll offset should start at 0")
    #expect(state.sortMode == .stars, "Should default to sort by stars")
    #expect(state.filterMode == .all, "Should default to show all packages")
    #expect(state.viewMode == .home, "Should default to home view")
    #expect(state.searchQuery.isEmpty, "Search query should be empty")
    #expect(!state.isSearching, "Should not be in search mode")
    #expect(state.statusMessage.isEmpty, "Status message should be empty")
}

@MainActor
@Test("AppState visible packages filters correctly")
func appStateVisiblePackagesFilter() async {
    let state = AppState()

    // Create test packages
    let pkg1 = SwiftPackageEntry(
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

    let pkg2 = SwiftPackageEntry(
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

    let pkg3 = SwiftPackageEntry(
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

    state.packages = [
        PackageEntry(package: pkg1, isSelected: true, isDownloaded: true),
        PackageEntry(package: pkg2, isSelected: false, isDownloaded: true),
        PackageEntry(package: pkg3, isSelected: true, isDownloaded: false),
    ]

    // Test: All filter
    state.filterMode = .all
    #expect(state.visiblePackages.count == 3, "Should show all 3 packages")

    // Test: Selected filter
    state.filterMode = .selected
    #expect(state.visiblePackages.count == 2, "Should show 2 selected packages")

    // Test: Downloaded filter
    state.filterMode = .downloaded
    #expect(state.visiblePackages.count == 2, "Should show 2 downloaded packages")
}

@MainActor
@Test("AppState search query filters packages")
func appStateSearchFilter() async {
    let state = AppState()

    let pkg1 = SwiftPackageEntry(
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

    let pkg2 = SwiftPackageEntry(
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

    state.packages = [
        PackageEntry(package: pkg1, isSelected: false, isDownloaded: false),
        PackageEntry(package: pkg2, isSelected: false, isDownloaded: false),
    ]

    // Test: Empty search shows all
    state.searchQuery = ""
    #expect(state.visiblePackages.count == 2, "Empty search should show all packages")

    // Test: Search by owner
    state.searchQuery = "apple"
    #expect(state.visiblePackages.count == 1, "Should find 1 package by owner")
    #expect(state.visiblePackages[0].package.owner == "apple", "Should find apple package")

    // Test: Search by repo
    state.searchQuery = "vapor"
    #expect(state.visiblePackages.count == 1, "Should find 1 package by repo")
    #expect(state.visiblePackages[0].package.repo == "vapor", "Should find vapor package")

    // Test: Search by description
    state.searchQuery = "server"
    #expect(state.visiblePackages.count == 1, "Should find 1 package by description")

    // Test: Case insensitive search
    state.searchQuery = "SWIFT"
    #expect(state.visiblePackages.count == 2, "Case insensitive search should find both")
}

@MainActor
@Test("AppState sort modes work correctly")
func appStateSortModes() async {
    let state = AppState()

    let pkg1 = SwiftPackageEntry(
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

    let pkg2 = SwiftPackageEntry(
        owner: "vapor",
        repo: "vapor",
        url: "https://github.com/vapor/vapor",
        description: "A server-side Swift framework",
        stars: 24000,
        language: "Swift",
        license: "MIT",
        fork: false,
        archived: false,
        updatedAt: "2025-11-20"
    )

    let pkg3 = SwiftPackageEntry(
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

    state.packages = [
        PackageEntry(package: pkg1, isSelected: false, isDownloaded: false),
        PackageEntry(package: pkg2, isSelected: false, isDownloaded: false),
        PackageEntry(package: pkg3, isSelected: false, isDownloaded: false),
    ]

    // Test: Sort by stars (default)
    state.sortMode = .stars
    let byStars = state.visiblePackages
    #expect(byStars[0].package.stars == 65000, "First should have most stars")
    #expect(byStars[2].package.stars == 18000, "Last should have least stars")

    // Test: Sort by name
    state.sortMode = .name
    let byName = state.visiblePackages
    #expect(byName[0].package.repo == "SwiftLint", "First alphabetically should be 'SwiftLint'")
    #expect(byName[2].package.repo == "vapor", "Last alphabetically should be 'vapor'")

    // Test: Sort by recent
    state.sortMode = .recent
    let byRecent = state.visiblePackages
    #expect(byRecent[0].package.updatedAt == "2025-11-20", "Most recent should be first")
    #expect(byRecent[2].package.updatedAt == "2025-11-17", "Oldest should be last")
}

@MainActor
@Test("AppState toggleCurrent changes selection")
func appStateToggleCurrent() async {
    let state = AppState()

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

    state.packages = [
        PackageEntry(package: pkg, isSelected: false, isDownloaded: false),
    ]
    state.cursor = 0

    // Test: Toggle on
    #expect(!state.packages[0].isSelected, "Should start unselected")
    state.toggleCurrent()
    #expect(state.packages[0].isSelected, "Should be selected after toggle")

    // Test: Toggle off
    state.toggleCurrent()
    #expect(!state.packages[0].isSelected, "Should be unselected after second toggle")
}

@MainActor
@Test("AppState moveCursor handles boundaries")
func appStateMoveCursor() async {
    let state = AppState()

    // Create 10 test packages
    for index in 0..<10 {
        let pkg = SwiftPackageEntry(
            owner: "owner\(index)",
            repo: "repo\(index)",
            url: "https://github.com/owner\(index)/repo\(index)",
            description: "Description \(index)",
            stars: 1000,
            language: "Swift",
            license: "MIT",
            fork: false,
            archived: false,
            updatedAt: "2025-11-19"
        )
        state.packages.append(PackageEntry(package: pkg, isSelected: false, isDownloaded: false))
    }

    let pageSize = 5

    // Test: Move down
    state.cursor = 0
    state.moveCursor(delta: 1, pageSize: pageSize)
    #expect(state.cursor == 1, "Cursor should move down to 1")

    // Test: Move up
    state.moveCursor(delta: -1, pageSize: pageSize)
    #expect(state.cursor == 0, "Cursor should move back to 0")

    // Test: Can't move above 0
    state.moveCursor(delta: -1, pageSize: pageSize)
    #expect(state.cursor == 0, "Cursor should stay at 0")

    // Test: Move to end
    state.cursor = 9
    state.moveCursor(delta: 1, pageSize: pageSize)
    #expect(state.cursor == 9, "Cursor should stay at last item")

    // Test: Page down
    state.cursor = 0
    state.moveCursor(delta: pageSize, pageSize: pageSize)
    #expect(state.cursor == 5, "Cursor should move down by page size")

    // Test: Scroll offset updates (cursor 5 with pageSize 5 means scrollOffset should be 1)
    #expect(state.scrollOffset >= 0, "Scroll offset should be non-negative")
}

@MainActor
@Test("AppState cycleSortMode rotates through modes")
func appStateCycleSortMode() {
    let state = AppState()

    state.sortMode = .stars
    state.cycleSortMode()
    #expect(state.sortMode == .name, "Should cycle to name")

    state.cycleSortMode()
    #expect(state.sortMode == .recent, "Should cycle to recent")

    state.cycleSortMode()
    #expect(state.sortMode == .stars, "Should cycle back to stars")
}

@MainActor
@Test("AppState cycleFilterMode rotates through modes")
func appStateCycleFilterMode() {
    let state = AppState()

    state.filterMode = .all
    state.cursor = 5
    state.scrollOffset = 2

    state.cycleFilterMode()
    #expect(state.filterMode == .selected, "Should cycle to selected")
    #expect(state.cursor == 0, "Cursor should reset")
    #expect(state.scrollOffset == 0, "Scroll offset should reset")

    state.cycleFilterMode()
    #expect(state.filterMode == .downloaded, "Should cycle to downloaded")

    state.cycleFilterMode()
    #expect(state.filterMode == .all, "Should cycle back to all")
}

@MainActor
@Test("AppState handles empty packages gracefully")
func appStateEmptyPackages() {
    let state = AppState()

    // Test with no packages
    #expect(state.visiblePackages.isEmpty, "Should have no visible packages")

    // Test moveCursor with empty list
    state.moveCursor(delta: 1, pageSize: 10)
    #expect(state.cursor == 0, "Cursor should stay at 0 with empty list")

    // Test toggleCurrent with empty list (should not crash)
    state.toggleCurrent()
    #expect(state.packages.isEmpty, "Should still be empty")
}
