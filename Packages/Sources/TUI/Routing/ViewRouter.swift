import Foundation

/// Handles view transitions and routing logic
@MainActor
enum ViewRouter {
    /// Process input and determine if a view transition should occur
    /// - Parameters:
    ///   - key: The input key
    ///   - state: Current app state
    ///   - homeCursor: Current home menu cursor position
    /// - Returns: New view mode if transition should occur, nil otherwise
    static func handleViewTransition(
        key: Key,
        state: AppState,
        homeCursor: Int
    ) -> ViewMode? {
        switch state.viewMode {
        case .home:
            return handleHomeTransition(key: key, homeCursor: homeCursor)
        case .library:
            return handleLibraryTransition(key: key)
        case .settings:
            return handleSettingsTransition(key: key, state: state)
        case .packages:
            return handlePackagesTransition(key: key, state: state)
        }
    }

    // MARK: - View-specific transition handlers

    private static func handleHomeTransition(key: Key, homeCursor: Int) -> ViewMode? {
        switch key {
        case .char("1"):
            return .packages
        case .char("2"):
            return .library
        case .char("3"):
            return .settings
        case .enter:
            return [ViewMode.packages, .library, .settings][homeCursor]
        default:
            return nil
        }
    }

    private static func handleLibraryTransition(key: Key) -> ViewMode? {
        switch key {
        case .char("h"), .escape:
            return .home
        default:
            return nil
        }
    }

    private static func handleSettingsTransition(key: Key, state: AppState) -> ViewMode? {
        // Don't allow navigation when editing
        guard !state.isEditingSettings else { return nil }

        switch key {
        case .char("h"), .escape:
            return .home
        default:
            return nil
        }
    }

    private static func handlePackagesTransition(key: Key, state: AppState) -> ViewMode? {
        // Don't allow navigation when searching
        guard !state.isSearching else { return nil }

        switch key {
        case .char("h"), .escape:
            return .home
        default:
            return nil
        }
    }
}
