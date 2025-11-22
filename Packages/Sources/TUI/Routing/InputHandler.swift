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
    // swiftlint:disable:next function_parameter_count
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

        // Handle view-specific input - only render if state changed
        let didChange: Bool
        switch state.viewMode {
        case .home:
            didChange = handleHomeInput(key: key, homeCursor: &homeCursor)
        case .library:
            didChange = handleLibraryInput(key: key, libraryCursor: &libraryCursor, artifacts: artifacts)
        case .settings:
            didChange = handleSettingsInput(key: key, state: state, settingsCursor: &settingsCursor)
        case .packages:
            didChange = handlePackagesInput(key: key, state: state, pageSize: pageSize)
        }

        return didChange ? .render : .continueRunning
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

    private static func handleHomeInput(key: Key, homeCursor: inout Int) -> Bool {
        let oldCursor = homeCursor
        switch key {
        case .arrowUp, .char("k"):
            homeCursor = max(0, homeCursor - 1)
        case .arrowDown, .char("j"):
            homeCursor = min(2, homeCursor + 1)
        default:
            return false
        }
        return homeCursor != oldCursor
    }

    // MARK: - Library View Input

    private static func handleLibraryInput(
        key: Key,
        libraryCursor: inout Int,
        artifacts: [ArtifactInfo]
    ) -> Bool {
        let oldCursor = libraryCursor
        switch key {
        case .arrowUp, .char("k"):
            libraryCursor = max(0, libraryCursor - 1)
        case .arrowDown, .char("j"):
            libraryCursor = min(artifacts.count - 1, libraryCursor + 1)
        case .char("o"), .enter:
            if libraryCursor < artifacts.count {
                openInFinder(url: artifacts[libraryCursor].path)
            }
            return false // Opening Finder doesn't change UI state
        default:
            return false
        }
        return libraryCursor != oldCursor
    }

    // MARK: - Settings View Input

    private static func handleSettingsInput(
        key: Key,
        state: AppState,
        settingsCursor: inout Int
    ) -> Bool {
        if state.isEditingSettings {
            return handleSettingsEditMode(key: key, state: state)
        } else {
            return handleSettingsNavigationMode(key: key, state: state, settingsCursor: &settingsCursor)
        }
    }

    private static func handleSettingsEditMode(key: Key, state: AppState) -> Bool {
        switch key {
        case .enter:
            saveSettings(state: state)
            return true
        case .escape:
            cancelSettingsEdit(state: state)
            return true
        case .backspace:
            if !state.editBuffer.isEmpty {
                state.editBuffer.removeLast()
                return true
            }
            return false
        case let .paste(text):
            let filtered = text.filter(\.isPrintable)
            if !filtered.isEmpty {
                state.editBuffer.append(contentsOf: filtered)
                return true
            }
            return false
        case let .char(character) where character.isPrintable:
            state.editBuffer.append(character)
            return true
        default:
            return false
        }
    }

    private static func handleSettingsNavigationMode(
        key: Key,
        state: AppState,
        settingsCursor: inout Int
    ) -> Bool {
        let oldCursor = settingsCursor
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
                return true
            }
            return false
        default:
            return false
        }
        return settingsCursor != oldCursor
    }

    // MARK: - Packages View Input

    private static func handlePackagesInput(key: Key, state: AppState, pageSize: Int) -> Bool {
        if state.isSearching {
            return handleSearchMode(key: key, state: state)
        } else {
            return handlePackagesNavigationMode(key: key, state: state, pageSize: pageSize)
        }
    }

    private static func handleSearchMode(key: Key, state: AppState) -> Bool {
        let pageSize = 20 // Approximate page size for navigation
        switch key {
        case .escape:
            // Clear search completely on Escape
            state.searchQuery = ""
            state.isSearching = false
            return true
        case .enter:
            // Keep results but exit search input mode
            state.isSearching = false
            return true
        case .arrowUp, .char("k"):
            // Allow navigation while searching
            return state.moveCursor(delta: -1, pageSize: pageSize)
        case .arrowDown, .char("j"):
            // Allow navigation while searching
            return state.moveCursor(delta: 1, pageSize: pageSize)
        case .arrowLeft, .pageUp:
            // Page up while searching
            return state.moveCursor(delta: -pageSize, pageSize: pageSize)
        case .arrowRight, .pageDown:
            // Page down while searching
            return state.moveCursor(delta: pageSize, pageSize: pageSize)
        case .ctrl("o"):
            // Open current package in browser while searching (Ctrl+O to avoid conflict with 'o' character in search)
            openCurrentPackageInBrowser(state: state)
            return false // Opening browser doesn't change UI
        case .backspace:
            if !state.searchQuery.isEmpty {
                state.searchQuery.removeLast()
                state.cursor = 0
                state.scrollOffset = 0
                // Auto-exit search mode when query becomes empty
                if state.searchQuery.isEmpty {
                    state.isSearching = false
                }
                return true
            }
            return false
        case let .char(character) where
            character.isLetter || character.isNumber || character.isWhitespace || "-_./".contains(character):
            state.searchQuery.append(character)
            state.cursor = 0
            state.scrollOffset = 0
            return true
        default:
            return false
        }
    }

    private static func handlePackagesNavigationMode(key: Key, state: AppState, pageSize: Int) -> Bool {
        switch key {
        case .arrowUp, .char("k"):
            return state.moveCursor(delta: -1, pageSize: pageSize)
        case .arrowDown, .char("j"):
            return state.moveCursor(delta: 1, pageSize: pageSize)
        case .arrowLeft, .pageUp:
            return state.moveCursor(delta: -pageSize, pageSize: pageSize)
        case .arrowRight, .pageDown:
            return state.moveCursor(delta: pageSize, pageSize: pageSize)
        case .homeKey, .ctrl("a"):
            return state.moveCursor(delta: -state.cursor, pageSize: pageSize)
        case .endKey, .ctrl("e"):
            let lastIndex = state.visiblePackages.count - 1
            return state.moveCursor(delta: lastIndex - state.cursor, pageSize: pageSize)
        case .space:
            state.toggleCurrent()
            return true
        case .char("f"):
            state.cycleFilterMode()
            return true
        case .char("s"):
            state.cycleSortMode()
            return true
        case .char("w"):
            do {
                try saveSelections(state: state)
            } catch {
                state.statusMessage = "❌ Failed to save: \(error.localizedDescription)"
            }
            return true
        case .char("/"):
            state.isSearching = true
            return true
        case .char("o"), .enter:
            openCurrentPackageInBrowser(state: state)
            return false // Opening browser doesn't change UI
        default:
            return false
        }
    }

    // MARK: - Settings Helpers

    private static func saveSettings(state: AppState) {
        // Debug: show what we're validating
        let trimmedBuffer = state.editBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if ConfigManager.validateBasePath(trimmedBuffer) {
            let expandedPath = ConfigManager.expandPath(trimmedBuffer)
            state.baseDirectory = expandedPath
            let newConfig = ConfigManager.TUIConfig(baseDirectory: expandedPath)
            do {
                try ConfigManager.save(newConfig)
                state.needsReload = true
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
            // Show the actual path that failed validation for debugging
            state.statusMessage = "❌ Invalid path '\(trimmedBuffer)' - must be absolute or start with ~"
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
