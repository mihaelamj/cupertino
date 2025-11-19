@testable import Core
import Foundation
import Testing
@testable import TUI

// MARK: - HomeView Tests

@Test("HomeView renders with basic stats")
func homeViewBasicRender() {
    let view = HomeView()
    let stats = HomeStats(
        totalPackages: 100,
        selectedPackages: 10,
        downloadedPackages: 5,
        artifactCount: 3,
        totalSize: 1024 * 1024 * 100 // 100 MB
    )

    let output = view.render(cursor: 0, width: 80, height: 24, stats: stats)

    #expect(!output.isEmpty, "HomeView should produce output")
    #expect(output.contains("Cupertino"), "Should contain Cupertino title")
    #expect(output.contains("100"), "Should contain total packages count")
}

@Test("HomeView renders menu items")
func homeViewMenuItems() {
    let view = HomeView()
    let stats = HomeStats(totalPackages: 0, selectedPackages: 0, downloadedPackages: 0, artifactCount: 0, totalSize: 0)

    let output = view.render(cursor: 0, width: 80, height: 24, stats: stats)

    #expect(output.contains("Packages"), "Should contain Packages menu item")
    #expect(output.contains("Library"), "Should contain Library menu item")
    #expect(output.contains("Settings"), "Should contain Settings menu item")
}

@Test("HomeView handles different cursor positions")
func homeViewCursorPositions() {
    let view = HomeView()
    let stats = HomeStats(totalPackages: 0, selectedPackages: 0, downloadedPackages: 0, artifactCount: 0, totalSize: 0)

    let output0 = view.render(cursor: 0, width: 80, height: 24, stats: stats)
    let output1 = view.render(cursor: 1, width: 80, height: 24, stats: stats)
    let output2 = view.render(cursor: 2, width: 80, height: 24, stats: stats)

    #expect(output0 != output1, "Different cursor positions should produce different output")
    #expect(output1 != output2, "Different cursor positions should produce different output")
}

// MARK: - SettingsView Tests

@Test("SettingsView renders without editing")
func settingsViewNormalMode() {
    let view = SettingsView()

    let output = view.render(
        cursor: 0,
        width: 80,
        height: 24,
        baseDirectory: "/test/path",
        isEditing: false,
        editBuffer: "",
        statusMessage: ""
    )

    #expect(!output.isEmpty, "SettingsView should produce output")
    #expect(output.contains("Settings"), "Should contain Settings title")
    #expect(output.contains("/test/path"), "Should display base directory")
    #expect(output.contains("Base Directory"), "Should show base directory label")
}

@Test("SettingsView renders with edit mode")
func settingsViewEditMode() {
    let view = SettingsView()

    let output = view.render(
        cursor: 0,
        width: 80,
        height: 24,
        baseDirectory: "/test/path",
        isEditing: true,
        editBuffer: "/new/path",
        statusMessage: ""
    )

    #expect(output.contains("/new/path"), "Should display edit buffer")
    #expect(output.contains("█"), "Should show cursor in edit mode")
    #expect(output.contains("Enter:Save"), "Should show save instruction")
    #expect(output.contains("Esc:Cancel"), "Should show cancel instruction")
}

@Test("SettingsView shows status message")
func settingsViewStatusMessage() {
    let view = SettingsView()

    let output = view.render(
        cursor: 0,
        width: 80,
        height: 24,
        baseDirectory: "/test/path",
        isEditing: false,
        editBuffer: "",
        statusMessage: "✅ Saved successfully"
    )

    #expect(output.contains("✅ Saved successfully"), "Should display status message")
}

@Test("SettingsView shows read-only items")
func settingsViewReadOnlyItems() {
    let view = SettingsView()

    let output = view.render(
        cursor: 0,
        width: 80,
        height: 24,
        baseDirectory: "/test/path",
        isEditing: false,
        editBuffer: "",
        statusMessage: ""
    )

    #expect(output.contains("read-only"), "Should mark non-editable items as read-only")
    #expect(output.contains("docs"), "Should show docs directory")
    #expect(output.contains("packages"), "Should show packages directory")
}

@Test("SettingsView handles different terminal widths")
func settingsViewDifferentWidths() {
    let view = SettingsView()

    let output80 = view.render(cursor: 0, width: 80, height: 24, baseDirectory: "/test", isEditing: false, editBuffer: "", statusMessage: "")
    let output120 = view.render(cursor: 0, width: 120, height: 24, baseDirectory: "/test", isEditing: false, editBuffer: "", statusMessage: "")

    #expect(output80.count != output120.count, "Different widths should produce different output sizes")
}

// MARK: - LibraryView Tests

@Test("LibraryView renders empty artifacts")
func libraryViewEmptyArtifacts() {
    let view = LibraryView()
    let artifacts: [ArtifactInfo] = []

    let output = view.render(artifacts: artifacts, cursor: 0, width: 80, height: 24)

    #expect(!output.isEmpty, "LibraryView should produce output even when empty")
    #expect(output.contains("Library"), "Should contain Library title")
}

@Test("LibraryView renders with artifacts")
func libraryViewWithArtifacts() {
    let view = LibraryView()
    let artifacts = [
        ArtifactInfo(name: "Apple Documentation", path: URL(fileURLWithPath: "/test/docs"), itemCount: 100, sizeBytes: 1024 * 1024),
        ArtifactInfo(name: "Swift Evolution", path: URL(fileURLWithPath: "/test/evolution"), itemCount: 50, sizeBytes: 512 * 1024),
    ]

    let output = view.render(artifacts: artifacts, cursor: 0, width: 80, height: 24)

    #expect(output.contains("Apple Documentation"), "Should show artifact name")
    #expect(output.contains("Swift Evolution"), "Should show artifact name")
    #expect(output.contains("100"), "Should show item count")
    #expect(output.contains("50"), "Should show item count")
}

@Test("LibraryView shows sizes in readable format")
func libraryViewReadableSizes() {
    let view = LibraryView()
    let artifacts = [
        ArtifactInfo(name: "Test", path: URL(fileURLWithPath: "/test"), itemCount: 1, sizeBytes: 1024 * 1024 * 1024), // 1 GB
    ]

    let output = view.render(artifacts: artifacts, cursor: 0, width: 80, height: 24)

    // Should show size in GB, MB, or KB
    let hasSizeIndicator = output.contains("GB") || output.contains("MB") || output.contains("KB")
    #expect(hasSizeIndicator, "Should show size with unit")
}

// MARK: - PackageView Tests

@Test("PackageView renders empty state")
func packageViewEmptyState() {
    let view = PackageView()
    let state = AppState()

    let output = view.render(state: state, width: 80, height: 24)

    #expect(!output.isEmpty, "PackageView should produce output even when empty")
}

@Test("PackageView renders with packages")
func packageViewWithPackages() {
    let view = PackageView()
    let state = AppState()

    let pkg1 = SwiftPackageEntry(
        owner: "apple",
        repo: "swift",
        url: "https://github.com/apple/swift",
        description: "The Swift Programming Language",
        stars: 60000,
        language: "C++",
        license: "Apache-2.0",
        fork: false,
        archived: false,
        updatedAt: "2024-01-01"
    )

    state.packages = [
        PackageEntry(package: pkg1, isSelected: false, isDownloaded: false),
    ]

    let output = view.render(state: state, width: 80, height: 24)

    #expect(output.contains("apple"), "Should show package owner")
    #expect(output.contains("swift"), "Should show package repo")
    // NumberFormatter formats numbers with locale-specific separators (e.g., "60,000")
    #expect(output.contains("60") && output.contains("000"), "Should show star count")
}

@Test("PackageView shows selection indicator")
func packageViewSelectionIndicator() {
    let view = PackageView()
    let state = AppState()

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "package",
        url: "https://github.com/test/package",
        description: nil,
        stars: 100,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [
        PackageEntry(package: pkg, isSelected: true, isDownloaded: false),
    ]

    let output = view.render(state: state, width: 80, height: 24)

    #expect(output.contains("★") || output.contains("[★]"), "Should show selection indicator")
}

@Test("PackageView shows download indicator")
func packageViewDownloadIndicator() {
    let view = PackageView()
    let state = AppState()

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "package",
        url: "https://github.com/test/package",
        description: nil,
        stars: 100,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [
        PackageEntry(package: pkg, isSelected: false, isDownloaded: true),
    ]

    let output = view.render(state: state, width: 80, height: 24)

    #expect(output.contains("📦"), "Should show download indicator")
}

@Test("PackageView shows help footer")
func packageViewHelpFooter() {
    let view = PackageView()
    let state = AppState()

    let output = view.render(state: state, width: 80, height: 24)

    #expect(output.contains("Space") || output.contains("toggle"), "Should show help text")
}

// MARK: - View Box Drawing Tests

@Test("All views use box drawing characters")
func viewsUseBoxDrawing() {
    let homeView = HomeView()
    let settingsView = SettingsView()
    let libraryView = LibraryView()
    let packageView = PackageView()

    let homeOutput = homeView.render(
        cursor: 0,
        width: 80,
        height: 24,
        stats: HomeStats(totalPackages: 0, selectedPackages: 0, downloadedPackages: 0, artifactCount: 0, totalSize: 0)
    )
    let settingsOutput = settingsView.render(cursor: 0, width: 80, height: 24, baseDirectory: "/test", isEditing: false, editBuffer: "", statusMessage: "")
    let libraryOutput = libraryView.render(artifacts: [], cursor: 0, width: 80, height: 24)
    let packageOutput = packageView.render(state: AppState(), width: 80, height: 24)

    // All views should use box drawing
    #expect(homeOutput.contains(Box.horizontal), "HomeView should use box drawing")
    #expect(settingsOutput.contains(Box.horizontal), "SettingsView should use box drawing")
    #expect(libraryOutput.contains(Box.horizontal), "LibraryView should use box drawing")
    #expect(packageOutput.contains(Box.horizontal), "PackageView should use box drawing")
}
