@testable import Core
import Foundation
import Testing
import TestSupport
@testable import TUI

// MARK: - InputHandler Tests

@MainActor
@Test("InputHandler detects quit from q key")
func inputHandlerQuitQ() {
    let state = AppState()
    state.viewMode = .home
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    let result = InputHandler.handleInput(
        .char("q"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(result == .quit, "Pressing 'q' should quit")
}

@MainActor
@Test("InputHandler detects quit from ctrl-c")
func inputHandlerQuitCtrlC() {
    let state = AppState()
    state.viewMode = .packages
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    let result = InputHandler.handleInput(
        .ctrl("c"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(result == .quit, "Pressing ctrl-c should quit")
}

@MainActor
@Test("InputHandler detects quit from escape in home view")
func inputHandlerQuitEscapeHome() {
    let state = AppState()
    state.viewMode = .home
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    let result = InputHandler.handleInput(
        .escape,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(result == .quit, "Pressing escape in home view should quit")
}

@MainActor
@Test("InputHandler moves home cursor up with k")
func inputHandlerHomeCursorUpK() {
    let state = AppState()
    state.viewMode = .home
    var homeCursor = 2
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .char("k"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(homeCursor == 1, "k should move cursor up")
}

@MainActor
@Test("InputHandler moves home cursor down with j")
func inputHandlerHomeCursorDownJ() {
    let state = AppState()
    state.viewMode = .home
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .char("j"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(homeCursor == 1, "j should move cursor down")
}

@MainActor
@Test("InputHandler clamps home cursor at boundaries")
func inputHandlerHomeCursorBoundaries() {
    let state = AppState()
    state.viewMode = .home
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    // Try to move up from 0
    _ = InputHandler.handleInput(
        .arrowUp,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )
    #expect(homeCursor == 0, "Cursor should stay at 0")

    // Move to max (3) - packages, library, archive, settings = 4 items
    homeCursor = 3
    _ = InputHandler.handleInput(
        .arrowDown,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )
    #expect(homeCursor == 3, "Cursor should stay at max (3)")
}

@MainActor
@Test("InputHandler moves library cursor")
func inputHandlerLibraryCursor() {
    let state = AppState()
    state.viewMode = .library
    var homeCursor = 0
    var libraryCursor = 1
    var settingsCursor = 0

    let artifacts = [
        ArtifactInfo(name: "Test1", path: URL(fileURLWithPath: "/tmp"), itemCount: 1, sizeBytes: 100),
        ArtifactInfo(name: "Test2", path: URL(fileURLWithPath: "/tmp"), itemCount: 2, sizeBytes: 200),
        ArtifactInfo(name: "Test3", path: URL(fileURLWithPath: "/tmp"), itemCount: 3, sizeBytes: 300),
    ]

    // Move up
    _ = InputHandler.handleInput(
        .char("k"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: artifacts,
        pageSize: 10
    )
    #expect(libraryCursor == 0, "k should move library cursor up")

    // Move down
    _ = InputHandler.handleInput(
        .char("j"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: artifacts,
        pageSize: 10
    )
    #expect(libraryCursor == 1, "j should move library cursor down")
}

@MainActor
@Test("InputHandler enters settings edit mode with e key")
func inputHandlerSettingsEditMode() {
    let state = AppState()
    state.viewMode = .settings
    state.baseDirectory = "/test/path"
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0 // Cursor on base directory

    _ = InputHandler.handleInput(
        .char("e"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.isEditingSettings, "Should enter edit mode")
    #expect(state.editBuffer == "/test/path", "Edit buffer should be populated with current path")
}

@MainActor
@Test("InputHandler does not enter edit mode when cursor not on base directory")
func inputHandlerSettingsEditModeWrongCursor() {
    let state = AppState()
    state.viewMode = .settings
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 1 // Not on base directory (cursor 0)

    _ = InputHandler.handleInput(
        .char("e"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(!state.isEditingSettings, "Should not enter edit mode")
}

@MainActor
@Test("InputHandler handles backspace in settings edit mode")
func inputHandlerSettingsBackspace() {
    let state = AppState()
    state.viewMode = .settings
    state.isEditingSettings = true
    state.editBuffer = "test"
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .backspace,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.editBuffer == "tes", "Backspace should remove last character")
}

@MainActor
@Test("InputHandler handles character input in settings edit mode")
func inputHandlerSettingsCharInput() {
    let state = AppState()
    state.viewMode = .settings
    state.isEditingSettings = true
    state.editBuffer = "/test"
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .char("/"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.editBuffer == "/test/", "Should append character to buffer")
}

@MainActor
@Test("InputHandler handles paste in settings edit mode")
func inputHandlerSettingsPaste() {
    let state = AppState()
    state.viewMode = .settings
    state.isEditingSettings = true
    state.editBuffer = ""
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .paste("/Users/test/Documents"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.editBuffer == "/Users/test/Documents", "Should paste full path")
}

@MainActor
@Test("InputHandler cancels settings edit on escape")
func inputHandlerSettingsCancelEdit() {
    let state = AppState()
    state.viewMode = .settings
    state.isEditingSettings = true
    state.editBuffer = "changed"
    state.statusMessage = "test"
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .escape,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(!state.isEditingSettings, "Should exit edit mode")
    #expect(state.editBuffer.isEmpty, "Edit buffer should be cleared")
    #expect(state.statusMessage.isEmpty, "Status message should be cleared")
}

@MainActor
@Test("InputHandler enters search mode with slash key")
func inputHandlerEnterSearchMode() {
    let state = AppState()
    state.viewMode = .packages
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .char("/"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.isSearching, "Should enter search mode")
}

@MainActor
@Test("InputHandler exits search mode on escape")
func inputHandlerExitSearchMode() {
    let state = AppState()
    state.viewMode = .packages
    state.isSearching = true
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .escape,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(!state.isSearching, "Should exit search mode")
}

@MainActor
@Test("InputHandler handles search query input")
func inputHandlerSearchQueryInput() {
    let state = AppState()
    state.viewMode = .packages
    state.isSearching = true
    state.searchQuery = ""
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .char("s"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.searchQuery == "s", "Should append character to search query")
    #expect(state.cursor == 0, "Cursor should reset to 0")
    #expect(state.scrollOffset == 0, "Scroll offset should reset to 0")
}

@MainActor
@Test("InputHandler handles backspace in search mode")
func inputHandlerSearchBackspace() {
    let state = AppState()
    state.viewMode = .packages
    state.isSearching = true
    state.searchQuery = "test"
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .backspace,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.searchQuery == "tes", "Should remove last character from query")
}

@MainActor
@Test("InputHandler auto-exits search when query becomes empty")
func inputHandlerSearchAutoExit() {
    let state = AppState()
    state.viewMode = .packages
    state.isSearching = true
    state.searchQuery = "a"
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .backspace,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.searchQuery.isEmpty, "Query should be empty")
    #expect(!state.isSearching, "Should auto-exit search mode")
}

@MainActor
@Test("InputHandler toggles package selection with space")
func inputHandlerToggleSelection() {
    let state = AppState()
    state.viewMode = .packages

    let pkg = SwiftPackageEntry(
        owner: "apple",
        repo: "swift",
        url: "https://github.com/apple/swift",
        description: "Test",
        stars: 1000,
        language: "Swift",
        license: "Apache-2.0",
        fork: false,
        archived: false,
        updatedAt: "2025-11-19"
    )
    state.packages = [PackageEntry(package: pkg, isSelected: false, isDownloaded: false)]
    state.cursor = 0

    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .space,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.packages[0].isSelected, "Package should be selected")
}

@MainActor
@Test("InputHandler cycles filter mode with f key")
func inputHandlerCycleFilter() {
    let state = AppState()
    state.viewMode = .packages
    state.filterMode = .all
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .char("f"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.filterMode == .selected, "Should cycle to selected filter")
}

@MainActor
@Test("InputHandler cycles sort mode with s key")
func inputHandlerCycleSort() {
    let state = AppState()
    state.viewMode = .packages
    state.isSearching = false
    state.sortMode = .stars
    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    _ = InputHandler.handleInput(
        .char("s"),
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )

    #expect(state.sortMode == .name, "Should cycle to name sort")
}

@MainActor
@Test("InputHandler moves package cursor with arrow keys")
func inputHandlerPackageCursorMovement() {
    let state = AppState()
    state.viewMode = .packages
    state.cursor = 5

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "test",
        url: "https://github.com/test/test",
        description: "Test",
        stars: 100,
        language: "Swift",
        license: "MIT",
        fork: false,
        archived: false,
        updatedAt: "2025-11-19"
    )
    state.packages = Array(repeating: PackageEntry(package: pkg, isSelected: false, isDownloaded: false), count: 20)

    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0

    // Move up
    _ = InputHandler.handleInput(
        .arrowUp,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )
    #expect(state.cursor == 4, "Arrow up should move cursor up")

    // Move down
    _ = InputHandler.handleInput(
        .arrowDown,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: 10
    )
    #expect(state.cursor == 5, "Arrow down should move cursor down")
}

@MainActor
@Test("InputHandler handles page up and page down")
func inputHandlerPageNavigation() {
    let state = AppState()
    state.viewMode = .packages
    state.cursor = 0

    let pkg = SwiftPackageEntry(
        owner: "test",
        repo: "test",
        url: "https://github.com/test/test",
        description: "Test",
        stars: 100,
        language: "Swift",
        license: "MIT",
        fork: false,
        archived: false,
        updatedAt: "2025-11-19"
    )
    state.packages = Array(repeating: PackageEntry(package: pkg, isSelected: false, isDownloaded: false), count: 100)

    var homeCursor = 0
    var libraryCursor = 0
    var settingsCursor = 0
    let pageSize = 10

    // Page down
    _ = InputHandler.handleInput(
        .pageDown,
        state: state,
        homeCursor: &homeCursor,
        libraryCursor: &libraryCursor,
        settingsCursor: &settingsCursor,
        artifacts: [],
        pageSize: pageSize
    )
    #expect(state.cursor == pageSize, "Page down should move by page size")
}
