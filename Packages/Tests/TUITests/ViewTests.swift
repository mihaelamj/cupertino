@testable import Core
import Foundation
import Testing
@testable import TUI

// MARK: - HomeView Tests

@MainActor
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

@MainActor
@Test("HomeView renders menu items")
func homeViewMenuItems() {
    let view = HomeView()
    let stats = HomeStats(totalPackages: 0, selectedPackages: 0, downloadedPackages: 0, artifactCount: 0, totalSize: 0)

    let output = view.render(cursor: 0, width: 80, height: 24, stats: stats)

    #expect(output.contains("Packages"), "Should contain Packages menu item")
    #expect(output.contains("Library"), "Should contain Library menu item")
    #expect(output.contains("Settings"), "Should contain Settings menu item")
}

@MainActor
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

@MainActor
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

@MainActor
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

@MainActor
@Test("SettingsView handles different terminal widths")
func settingsViewDifferentWidths() {
    let view = SettingsView()

    let output80 = view.render(cursor: 0, width: 80, height: 24, baseDirectory: "/test", isEditing: false, editBuffer: "", statusMessage: "")
    let output120 = view.render(cursor: 0, width: 120, height: 24, baseDirectory: "/test", isEditing: false, editBuffer: "", statusMessage: "")

    #expect(output80.count != output120.count, "Different widths should produce different output sizes")
}

// MARK: - LibraryView Tests

@MainActor
@Test("LibraryView renders empty artifacts")
func libraryViewEmptyArtifacts() {
    let view = LibraryView()
    let artifacts: [ArtifactInfo] = []

    let output = view.render(artifacts: artifacts, cursor: 0, width: 80, height: 24)

    #expect(!output.isEmpty, "LibraryView should produce output even when empty")
    #expect(output.contains("Library"), "Should contain Library title")
}

@MainActor
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

@MainActor
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

@MainActor
@Test("PackageView renders empty state")
func packageViewEmptyState() {
    let view = PackageView()
    let state = AppState()

    let output = view.render(state: state, width: 80, height: 24)

    #expect(!output.isEmpty, "PackageView should produce output even when empty")
}

@MainActor
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

@MainActor
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

    #expect(output.contains("[*]"), "Should show selection indicator")
}

@MainActor
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

    #expect(output.contains("[D]"), "Should show download indicator")
}

@MainActor
@Test("PackageView shows help footer")
func packageViewHelpFooter() {
    let view = PackageView()
    let state = AppState()

    let output = view.render(state: state, width: 80, height: 24)

    #expect(output.contains("Space") || output.contains("toggle"), "Should show help text")
}

// MARK: - View Box Drawing Tests

@MainActor
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

// MARK: - Box Drawing Width Tests

/// Strip ANSI escape codes from a string
func stripAnsiCodes(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
}

/// Get visible width of a line (without ANSI codes)
func visibleWidth(_ line: String) -> Int {
    stripAnsiCodes(line).count
}

@MainActor
@Test("PackageView lines have consistent width")
func packageViewLineWidth() {
    let view = PackageView()
    let state = AppState()

    // Add packages with varying name lengths
    let packages = [
        SwiftPackageEntry(
            owner: "a",
            repo: "b",
            url: "https://github.com/a/b",
            description: "Short",
            stars: 100,
            language: nil,
            license: nil,
            fork: false,
            archived: false,
            updatedAt: nil
        ),
        SwiftPackageEntry(
            owner: "verylongowner",
            repo: "verylongrepo",
            url: "https://github.com/verylongowner/verylongrepo",
            description: "Long",
            stars: 50000,
            language: nil,
            license: nil,
            fork: false,
            archived: false,
            updatedAt: nil
        ),
        SwiftPackageEntry(
            owner: "apple",
            repo: "swift",
            url: "https://github.com/apple/swift",
            description: "Medium",
            stars: 60000,
            language: nil,
            license: nil,
            fork: false,
            archived: false,
            updatedAt: nil
        ),
    ]

    state.packages = packages.map { PackageEntry(package: $0, isSelected: false, isDownloaded: false) }

    let width = 100
    let output = view.render(state: state, width: width, height: 24)

    // Split into lines and check package lines
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

    // Find lines that contain package entries (they have "│ [ ]" pattern)
    let packageLines = lines.filter { line in
        let plain = stripAnsiCodes(line)
        return plain.contains("│ [ ]") || plain.contains("│ [*]")
    }

    // All package lines should have the same visible width
    var widths = Set<Int>()
    for line in packageLines {
        let lineWidth = visibleWidth(line)
        widths.insert(lineWidth)
    }

    #expect(widths.count == 1, "All package lines should have the same width, found: \(widths)")
    if let actualWidth = widths.first {
        #expect(actualWidth == width, "Package lines should match terminal width (\(width)), got \(actualWidth)")
    }
}

@MainActor
@Test("PackageView border alignment with different widths")
func packageViewBorderAlignment() {
    let view = PackageView()
    let state = AppState()

    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift",
        url: "https://github.com/apple/swift",
        description: "Test",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]

    // Test multiple widths
    for width in [80, 100, 120] {
        let output = view.render(state: state, width: width, height: 24)
        let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

        // Check that all lines have consistent width
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        let lineWidths = nonEmptyLines.map { visibleWidth($0) }

        for (index, lineWidth) in lineWidths.enumerated() {
            #expect(lineWidth == width, "Line \(index) at width \(width) should be \(width) chars, got \(lineWidth): '\(stripAnsiCodes(nonEmptyLines[index]))'")
        }
    }
}

@MainActor
@Test("All view lines match terminal width")
func allViewsMatchWidth() {
    let width = 100
    let height = 24

    // Test HomeView
    let homeView = HomeView()
    let homeOutput = homeView.render(
        cursor: 0,
        width: width,
        height: height,
        stats: HomeStats(totalPackages: 10, selectedPackages: 5, downloadedPackages: 3, artifactCount: 2, totalSize: 1024)
    )
    let homeLines = homeOutput.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    for (index, line) in homeLines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(
            lineWidth == width,
            "HomeView line \(index) should be \(width) chars, got \(lineWidth)"
        )
    }

    // Test SettingsView
    let settingsView = SettingsView()
    let settingsOutput = settingsView.render(
        cursor: 0,
        width: width,
        height: height,
        baseDirectory: "/test/path/to/directory",
        isEditing: false,
        editBuffer: "",
        statusMessage: ""
    )
    let settingsLines = settingsOutput.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    for (index, line) in settingsLines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(
            lineWidth == width,
            "SettingsView line \(index) should be \(width) chars, got \(lineWidth)"
        )
    }

    // Test LibraryView
    let libraryView = LibraryView()
    let artifacts = [
        ArtifactInfo(name: "Apple Documentation", path: URL(fileURLWithPath: "/test"), itemCount: 100, sizeBytes: 1024 * 1024),
    ]
    let libraryOutput = libraryView.render(artifacts: artifacts, cursor: 0, width: width, height: height)
    let libraryLines = libraryOutput.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    for (index, line) in libraryLines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(
            lineWidth == width,
            "LibraryView line \(index) should be \(width) chars, got \(lineWidth)"
        )
    }
}

// MARK: - State Variation Tests (Detect Subtle Bugs)

@MainActor
@Test("PackageView width with selected packages")
func packageViewSelectedState() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift",
        url: "https://github.com/apple/swift",
        description: "Test",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    // Test both selected and unselected
    for isSelected in [true, false] {
        state.packages = [PackageEntry(package: pkg, isSelected: isSelected, isDownloaded: false)]
        let output = view.render(state: state, width: width, height: 24)
        let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

        let packageLines = lines.filter { line in
            let plain = stripAnsiCodes(line)
            return plain.contains("│ [") && (plain.contains("[*]") || plain.contains("[ ]"))
        }

        for line in packageLines {
            let lineWidth = visibleWidth(line)
            #expect(
                lineWidth == width,
                "Selected=\(isSelected): Package line should be \(width) chars, got \(lineWidth)"
            )
        }
    }
}

@MainActor
@Test("PackageView width with downloaded packages")
func packageViewDownloadedState() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift",
        url: "https://github.com/apple/swift",
        description: "Test",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    // Test both downloaded and not downloaded
    for isDownloaded in [true, false] {
        state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: isDownloaded)]
        let output = view.render(state: state, width: width, height: 24)
        let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

        let packageLines = lines.filter { line in
            let plain = stripAnsiCodes(line)
            return plain.contains("│ [ ]") || plain.contains("│ [*]")
        }

        for line in packageLines {
            let lineWidth = visibleWidth(line)
            #expect(
                lineWidth == width,
                "Downloaded=\(isDownloaded): Package line should be \(width) chars, got \(lineWidth)"
            )
        }
    }
}

@MainActor
@Test("PackageView width with search highlighting")
func packageViewSearchHighlighting() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift-foundation",
        url: "https://github.com/apple/swift-foundation",
        description: "Test",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]
    state.searchQuery = "swift" // Should highlight "swift" in the package name
    state.cursor = 0

    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

    let packageLines = lines.filter { line in
        let plain = stripAnsiCodes(line)
        return plain.contains("│ [ ]") || plain.contains("│ [*]")
    }

    for line in packageLines {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "Package line with search highlighting should be \(width) chars, got \(lineWidth). Line: '\(stripAnsiCodes(line))'")
    }
}

@MainActor
@Test("PackageView width with search highlighting on selected line")
func packageViewSearchHighlightingOnSelected() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift-foundation",
        url: "https://github.com/apple/swift-foundation",
        description: "Test",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]
    state.searchQuery = "swift"
    state.cursor = 0 // Selected line with search highlighting

    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

    let packageLines = lines.filter { line in
        let plain = stripAnsiCodes(line)
        return plain.contains("│ [ ]") || plain.contains("│ [*]")
    }

    for line in packageLines {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "Selected line with search highlighting should be \(width) chars, got \(lineWidth)")
    }
}

@MainActor
@Test("PackageView width with very long package names")
func packageViewLongNames() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    // Very long name that will definitely need truncation
    let pkg = SwiftPackageEntry(
        owner: "verylongorganizationname",
        repo: "verylongrepositorynamethatshouldbetruncatedwithellipsis",
        url: "https://github.com/test/test",
        description: "Test",
        stars: 123456789, // Also very large star count
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]

    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

    let packageLines = lines.filter { line in
        let plain = stripAnsiCodes(line)
        return plain.contains("│ [ ]") || plain.contains("│ [*]")
    }

    for line in packageLines {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "Long package name should be truncated to \(width) chars total, got \(lineWidth)")

        // Also verify truncation actually happened
        let plain = stripAnsiCodes(line)
        #expect(plain.contains("…"), "Long name should contain ellipsis for truncation")
    }
}

@MainActor
@Test("PackageView component widths are exact")
func packageViewComponentWidths() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "pkg",
        url: "https://github.com/test/pkg",
        description: "Test",
        stars: 123,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    // Test unselected + not downloaded
    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]
    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

    let packageLine = lines.first { line in
        let plain = stripAnsiCodes(line)
        return plain.contains("│ [ ]")
    }

    if let line = packageLine {
        let plain = stripAnsiCodes(line)

        // Verify components are present and in correct positions
        #expect(plain.hasPrefix("│ "), "Line should start with '│ '")
        #expect(plain.hasSuffix(" │"), "Line should end with ' │'")
        #expect(plain.contains("[ ]"), "Line should contain checkbox '[ ]'")
        #expect(plain.contains("   ") || plain.contains("[D]"), "Line should contain download indicator")
        #expect(plain.contains(" * "), "Line should contain ' * ' star prefix")
    } else {
        #expect(Bool(false), "Should find at least one package line")
    }
}

@MainActor
@Test("PackageView width at minimum size")
func packageViewMinimumWidth() {
    let view = PackageView()
    let state = AppState()
    let width = 80 // Minimum guaranteed width

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "package",
        url: "https://github.com/test/package",
        description: "Test description",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]

    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

    for (index, line) in lines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "Line \(index) at minimum width should be \(width) chars, got \(lineWidth)")
    }
}

// MARK: - Helper Function Tests

@MainActor
@Test("stripAnsiCodes removes all ANSI escape sequences")
func stripAnsiCodesFunction() {
    // No ANSI codes
    #expect(stripAnsiCodes("hello") == "hello", "Plain text should remain unchanged")

    // Single color code
    let colored = "\u{001B}[33mhello\u{001B}[0m"
    #expect(stripAnsiCodes(colored) == "hello", "Should strip color codes")

    // Multiple ANSI codes
    let multiColor = "\u{001B}[31m\u{001B}[1mBold Red\u{001B}[0m"
    #expect(stripAnsiCodes(multiColor) == "Bold Red", "Should strip multiple codes")

    // ANSI codes in middle
    let mixed = "Hello \u{001B}[33mworld\u{001B}[0m!"
    #expect(stripAnsiCodes(mixed) == "Hello world!", "Should strip codes in middle")

    // Background colors
    let bgColor = "\u{001B}[44m\u{001B}[37mText\u{001B}[0m"
    #expect(stripAnsiCodes(bgColor) == "Text", "Should strip background colors")
}

@MainActor
@Test("visibleWidth calculates width without ANSI codes")
func visibleWidthFunction() {
    #expect(visibleWidth("hello") == 5, "Plain text width")

    let colored = "\u{001B}[33mhello\u{001B}[0m"
    #expect(visibleWidth(colored) == 5, "Colored text should count visible chars only")

    let highlighted = "\u{001B}[44m\u{001B}[30mtest\u{001B}[0m"
    #expect(visibleWidth(highlighted) == 4, "Highlighted text visible width")
}

// MARK: - Border Character Tests

@MainActor
@Test("PackageView uses correct box drawing characters")
func packageViewBoxCharacters() {
    let view = PackageView()
    let state = AppState()

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "pkg",
        url: "https://github.com/test/pkg",
        description: "Test",
        stars: 100,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]

    let output = view.render(state: state, width: 80, height: 24)

    // Should contain box drawing characters
    #expect(output.contains("┌"), "Should use top-left corner ┌")
    #expect(output.contains("┐"), "Should use top-right corner ┐")
    #expect(output.contains("└"), "Should use bottom-left corner └")
    #expect(output.contains("┘"), "Should use bottom-right corner ┘")
    #expect(output.contains("├"), "Should use left tee ├")
    #expect(output.contains("┤"), "Should use right tee ┤")
    #expect(output.contains("─"), "Should use horizontal line ─")
    #expect(output.contains("│"), "Should use vertical line │")
}

// MARK: - Extreme Edge Cases

@MainActor
@Test("PackageView with very large width")
func packageViewLargeWidth() {
    let view = PackageView()
    let state = AppState()
    let width = 200 // Very wide terminal

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "package",
        url: "https://github.com/test/package",
        description: "Test",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]

    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

    for (index, line) in lines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "Line \(index) at large width should be \(width) chars, got \(lineWidth)")
    }
}

@MainActor
@Test("PackageView with zero stars")
func packageViewZeroStars() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "package",
        url: "https://github.com/test/package",
        description: "Test",
        stars: 0, // Zero stars
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]

    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

    let packageLines = lines.filter { line in
        let plain = stripAnsiCodes(line)
        return plain.contains("│ [ ]") || plain.contains("│ [*]")
    }

    for line in packageLines {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "Package with 0 stars should be \(width) chars, got \(lineWidth)")
    }
}

@MainActor
@Test("PackageView with combined states")
func packageViewCombinedStates() {
    let view = PackageView()
    let state = AppState()
    let width = 100

    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift",
        url: "https://github.com/apple/swift",
        description: "Test",
        stars: 12345,
        language: nil,
        license: nil,
        fork: false,
        archived: false,
        updatedAt: nil
    )

    // Test: selected + downloaded + on cursor with search
    state.packages = [PackageEntry(package: pkg, isSelected: true, isDownloaded: true)]
    state.searchQuery = "swift"
    state.cursor = 0

    let output = view.render(state: state, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)

    let packageLines = lines.filter { line in
        let plain = stripAnsiCodes(line)
        return plain.contains("│ [*]") && plain.contains("[D]")
    }

    for line in packageLines {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "Combined state (selected+downloaded+search+cursor) should be \(width) chars, got \(lineWidth)")
    }
}

// MARK: - HomeView State Tests

@MainActor
@Test("HomeView with different cursor positions")
func homeViewCursorStates() {
    let homeView = HomeView()
    let width = 100
    let stats = HomeStats(totalPackages: 10, selectedPackages: 5, downloadedPackages: 3, artifactCount: 2, totalSize: 1024)

    for cursor in 0...2 {
        let output = homeView.render(cursor: cursor, width: width, height: 24, stats: stats)
        let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            let lineWidth = visibleWidth(line)
            #expect(lineWidth == width, "HomeView line \(index) with cursor=\(cursor) should be \(width) chars, got \(lineWidth)")
        }
    }
}

@MainActor
@Test("HomeView with large numbers")
func homeViewLargeNumbers() {
    let homeView = HomeView()
    let width = 100
    let stats = HomeStats(
        totalPackages: 999999,
        selectedPackages: 888888,
        downloadedPackages: 777777,
        artifactCount: 666,
        totalSize: 999999999999 // ~1TB
    )

    let output = homeView.render(cursor: 0, width: width, height: 24, stats: stats)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

    for (index, line) in lines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "HomeView with large numbers line \(index) should be \(width) chars, got \(lineWidth)")
    }
}

// MARK: - LibraryView State Tests

@MainActor
@Test("LibraryView with selected artifact")
func libraryViewSelectedState() {
    let libraryView = LibraryView()
    let width = 100
    let artifacts = [
        ArtifactInfo(name: "Apple Documentation", path: URL(fileURLWithPath: "/test1"), itemCount: 100, sizeBytes: 1024 * 1024),
        ArtifactInfo(name: "Swift Evolution", path: URL(fileURLWithPath: "/test2"), itemCount: 50, sizeBytes: 512 * 1024),
    ]

    // Test with different cursor positions (selecting different artifacts)
    for cursor in 0..<artifacts.count {
        let output = libraryView.render(artifacts: artifacts, cursor: cursor, width: width, height: 24)
        let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            let lineWidth = visibleWidth(line)
            #expect(lineWidth == width, "LibraryView line \(index) with cursor=\(cursor) should be \(width) chars, got \(lineWidth)")
        }
    }
}

@MainActor
@Test("LibraryView with very long artifact name")
func libraryViewLongName() {
    let libraryView = LibraryView()
    let width = 100
    let artifacts = [
        ArtifactInfo(
            name: "Very Long Artifact Name That Should Be Truncated Because It Exceeds Available Width",
            path: URL(fileURLWithPath: "/test"),
            itemCount: 999999,
            sizeBytes: 999999999999
        ),
    ]

    let output = libraryView.render(artifacts: artifacts, cursor: 0, width: width, height: 24)
    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

    for (index, line) in lines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "LibraryView with long name line \(index) should be \(width) chars, got \(lineWidth)")
    }
}

// MARK: - SettingsView State Tests

@MainActor
@Test("SettingsView in edit mode")
func settingsViewEditMode() {
    let settingsView = SettingsView()
    let width = 100

    let output = settingsView.render(
        cursor: 0,
        width: width,
        height: 24,
        baseDirectory: "/test/path",
        isEditing: true,
        editBuffer: "/new/path/being/edited",
        statusMessage: ""
    )

    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

    for (index, line) in lines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "SettingsView edit mode line \(index) should be \(width) chars, got \(lineWidth)")
    }
}

@MainActor
@Test("SettingsView with status message")
func settingsViewWithStatus() {
    let settingsView = SettingsView()
    let width = 100

    let output = settingsView.render(
        cursor: 0,
        width: width,
        height: 24,
        baseDirectory: "/test/path",
        isEditing: false,
        editBuffer: "",
        statusMessage: "✅ Settings saved successfully!"
    )

    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

    for (index, line) in lines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "SettingsView with status line \(index) should be \(width) chars, got \(lineWidth)")
    }
}

@MainActor
@Test("SettingsView with very long directory path")
func settingsViewLongPath() {
    let settingsView = SettingsView()
    let width = 100

    let longPath = "/very/long/directory/path/that/goes/on/and/on/and/should/be/truncated/properly/without/breaking/the/layout"

    let output = settingsView.render(
        cursor: 0,
        width: width,
        height: 24,
        baseDirectory: longPath,
        isEditing: false,
        editBuffer: "",
        statusMessage: ""
    )

    let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

    for (index, line) in lines.enumerated() {
        let lineWidth = visibleWidth(line)
        #expect(lineWidth == width, "SettingsView with long path line \(index) should be \(width) chars, got \(lineWidth)")
    }
}

@MainActor
@Test("SettingsView with different cursor positions")
func settingsViewCursorStates() {
    let settingsView = SettingsView()
    let width = 100

    // Test cursor on each setting (0-6)
    for cursor in 0...6 {
        let output = settingsView.render(
            cursor: cursor,
            width: width,
            height: 24,
            baseDirectory: "/test/path",
            isEditing: false,
            editBuffer: "",
            statusMessage: ""
        )

        let lines = output.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            let lineWidth = visibleWidth(line)
            #expect(lineWidth == width, "SettingsView line \(index) with cursor=\(cursor) should be \(width) chars, got \(lineWidth)")
        }
    }
}
