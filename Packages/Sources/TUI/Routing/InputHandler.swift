import Foundation

/// Result of input handling - either continue running, quit, or request render
enum InputResult {
    case continueRunning
    case quit
    case render
}

/// Handles all keyboard input and state mutations
@MainActor
enum InputHandler {
    /// Process a key input and mutate state accordingly
    /// - Parameters:
    ///   - key: The input key
    ///   - state: Current app state (will be mutated)
    ///   - homeCursor: Home menu cursor (passed as inout)
    ///   - libraryCursor: Library cursor (passed as inout)
    ///   - settingsCursor: Settings cursor (passed as inout)
    ///   - artifacts: Available artifacts for library view
    ///   - pageSize: Number of items visible per page
    /// - Returns: InputResult indicating what action to take
    static func handleInput(
        _ key: Key,
        state: AppState,
        homeCursor: inout Int,
        libraryCursor: inout Int,
        settingsCursor: inout Int,
        artifacts: [ArtifactInfo],
        pageSize: Int
    ) -> InputResult {
        // Check for quit commands
        if shouldQuit(key: key, state: state) {
            return .quit
        }

        // Handle view-specific input
        switch state.viewMode {
        case .home:
            handleHomeInput(key: key, homeCursor: &homeCursor)
        case .library:
            handleLibraryInput(key: key, libraryCursor: &libraryCursor, artifacts: artifacts)
        case .settings:
            handleSettingsInput(key: key, state: state, settingsCursor: &settingsCursor)
        case .packages:
            handlePackagesInput(key: key, state: state, pageSize: pageSize)
        }

        return .render
    }

    // MARK: - Quit Detection

    private static func shouldQuit(key: Key, state: AppState) -> Bool {
        switch key {
        case .char("q"), .ctrl("c"):
            return true
        case .escape:
            // Only quit from home view
            return state.viewMode == .home
        default:
            return false
        }
    }

    // MARK: - Home View Input

    private static func handleHomeInput(key: Key, homeCursor: inout Int) {
        switch key {
        case .arrowUp, .char("k"):
            homeCursor = max(0, homeCursor - 1)
        case .arrowDown, .char("j"):
            homeCursor = min(2, homeCursor + 1)
        default:
            break
        }
    }

    // MARK: - Library View Input

    private static func handleLibraryInput(
        key: Key,
        libraryCursor: inout Int,
        artifacts: [ArtifactInfo]
    ) {
        switch key {
        case .arrowUp, .char("k"):
            libraryCursor = max(0, libraryCursor - 1)
        case .arrowDown, .char("j"):
            libraryCursor = min(artifacts.count - 1, libraryCursor + 1)
        case .char("o"), .enter:
            if libraryCursor < artifacts.count {
                openInFinder(url: artifacts[libraryCursor].path)
            }
        default:
            break
        }
    }

    // MARK: - Settings View Input

    private static func handleSettingsInput(
        key: Key,
        state: AppState,
        settingsCursor: inout Int
    ) {
        if state.isEditingSettings {
            handleSettingsEditMode(key: key, state: state)
        } else {
            handleSettingsNavigationMode(key: key, state: state, settingsCursor: &settingsCursor)
        }
    }

    private static func handleSettingsEditMode(key: Key, state: AppState) {
        switch key {
        case .enter:
            saveSettings(state: state)
        case .escape:
            cancelSettingsEdit(state: state)
        case .backspace:
            if !state.editBuffer.isEmpty {
                state.editBuffer.removeLast()
            }
        case let .paste(text):
            let filtered = text.filter(\.isPrintable)
            state.editBuffer.append(contentsOf: filtered)
        case let .char(character) where character.isPrintable:
            state.editBuffer.append(character)
        default:
            break
        }
    }

    private static func handleSettingsNavigationMode(
        key: Key,
        state: AppState,
        settingsCursor: inout Int
    ) {
        switch key {
        case .arrowUp, .char("k"):
            settingsCursor = max(0, settingsCursor - 1)
        case .arrowDown, .char("j"):
            settingsCursor = min(6, settingsCursor + 1)
        case .char("e"):
            // Only allow editing base directory (cursor 0)
            if settingsCursor == 0 {
                state.isEditingSettings = true
                state.editBuffer = state.baseDirectory
            }
        default:
            break
        }
    }

    // MARK: - Packages View Input

    private static func handlePackagesInput(key: Key, state: AppState, pageSize: Int) {
        if state.isSearching {
            handleSearchMode(key: key, state: state)
        } else {
            handlePackagesNavigationMode(key: key, state: state, pageSize: pageSize)
        }
    }

    private static func handleSearchMode(key: Key, state: AppState) {
        switch key {
        case .escape, .enter:
            state.isSearching = false
        case .backspace:
            if !state.searchQuery.isEmpty {
                state.searchQuery.removeLast()
                state.cursor = 0
                state.scrollOffset = 0
                // Auto-exit search mode when query becomes empty
                if state.searchQuery.isEmpty {
                    state.isSearching = false
                }
            }
        case let .char(character) where character.isLetter || character.isNumber || character.isWhitespace || "-_./".contains(character):
            state.searchQuery.append(character)
            state.cursor = 0
            state.scrollOffset = 0
        default:
            break
        }
    }

    private static func handlePackagesNavigationMode(key: Key, state: AppState, pageSize: Int) {
        switch key {
        case .arrowUp, .char("k"):
            state.moveCursor(delta: -1, pageSize: pageSize)
        case .arrowDown, .char("j"):
            state.moveCursor(delta: 1, pageSize: pageSize)
        case .arrowLeft, .pageUp:
            state.moveCursor(delta: -pageSize, pageSize: pageSize)
        case .arrowRight, .pageDown:
            state.moveCursor(delta: pageSize, pageSize: pageSize)
        case .homeKey, .ctrl("a"):
            state.moveCursor(delta: -state.cursor, pageSize: pageSize)
        case .endKey, .ctrl("e"):
            let lastIndex = state.visiblePackages.count - 1
            state.moveCursor(delta: lastIndex - state.cursor, pageSize: pageSize)
        case .space:
            state.toggleCurrent()
        case .char("f"):
            state.cycleFilterMode()
        case .char("s"):
            state.cycleSortMode()
        case .char("w"):
            do {
                try saveSelections(state: state)
            } catch {
                state.statusMessage = "❌ Failed to save: \(error.localizedDescription)"
            }
        case .char("/"):
            state.isSearching = true
        case .char("o"), .enter:
            openCurrentPackageInBrowser(state: state)
        default:
            break
        }
    }

    // MARK: - Settings Helpers

    private static func saveSettings(state: AppState) {
        if ConfigManager.validateBasePath(state.editBuffer) {
            let expandedPath = ConfigManager.expandPath(state.editBuffer)
            state.baseDirectory = expandedPath
            let newConfig = ConfigManager.TUIConfig(baseDirectory: expandedPath)
            do {
                try ConfigManager.save(newConfig)
                state.statusMessage = Colors.brightCyan + "🔄 Reloading data from new location..." + Colors.reset
                state.isEditingSettings = false
                state.editBuffer = ""

                // Reload will happen in main loop
            } catch {
                state.statusMessage = "❌ Failed to save config: \(error.localizedDescription)"
                state.isEditingSettings = false
                state.editBuffer = ""
            }
        } else {
            state.statusMessage = "❌ Invalid path - must be absolute or start with ~"
            state.isEditingSettings = false
            state.editBuffer = ""
        }
    }

    private static func cancelSettingsEdit(state: AppState) {
        state.isEditingSettings = false
        state.editBuffer = ""
        state.statusMessage = ""
    }
}
