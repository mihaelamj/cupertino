import Core
import Foundation

enum FilterMode: String {
    case all = "All"
    case selected = "Selected"
    case downloaded = "Downloaded"
}

enum ViewMode {
    case home
    case packages
    case library
    case settings
}

/// App state for TUI
/// Note: @MainActor because TUI runs on main thread and state is shared across async calls
@MainActor
final class AppState {
    var packages: [PackageEntry] = []
    var cursor: Int = 0
    var scrollOffset: Int = 0
    var sortMode: SortMode = .stars
    var filterMode: FilterMode = .all
    var viewMode: ViewMode = .home
    var searchQuery: String = ""
    var showOnlySelected: Bool = false
    var statusMessage: String = ""
    var isSearching: Bool = false

    // Settings edit mode
    var isEditingSettings: Bool = false
    var editBuffer: String = ""
    var baseDirectory: String = ""
    var needsReload: Bool = false
    var needsScreenClear: Bool = false // Track when we need to force clear screen

    var visiblePackages: [PackageEntry] {
        var filtered = packages

        // Apply search filter (only searches owner/repo, not description)
        if !searchQuery.isEmpty {
            filtered = filtered.filter { entry in
                entry.package.owner.localizedCaseInsensitiveContains(searchQuery) ||
                    entry.package.repo.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Apply filter mode
        switch filterMode {
        case .all:
            break
        case .selected:
            filtered = filtered.filter(\.isSelected)
        case .downloaded:
            filtered = filtered.filter(\.isDownloaded)
        }

        // Apply sort
        switch sortMode {
        case .stars:
            return filtered.sorted { $0.package.stars > $1.package.stars }
        case .name:
            return filtered.sorted { $0.package.repo < $1.package.repo }
        case .recent:
            return filtered.sorted { ($0.package.updatedAt ?? "") > ($1.package.updatedAt ?? "") }
        }
    }

    func toggleCurrent() {
        let visible = visiblePackages
        guard cursor < visible.count else { return }

        if let index = packages.firstIndex(where: { $0.package.url == visible[cursor].package.url }) {
            packages[index].isSelected.toggle()
        }
    }

    func moveCursor(delta: Int, pageSize: Int) -> Bool {
        let visible = visiblePackages
        guard !visible.isEmpty else { return false }

        let oldCursor = cursor
        let oldScrollOffset = scrollOffset

        cursor = max(0, min(cursor + delta, visible.count - 1))

        // Simple scrolling: keep cursor visible, no fancy centering
        // Scroll down if cursor goes below visible area
        if cursor >= scrollOffset + pageSize {
            scrollOffset = cursor - pageSize + 1
        }
        // Scroll up if cursor goes above visible area
        else if cursor < scrollOffset {
            scrollOffset = cursor
        }

        // Return true only if cursor or scroll position changed
        return cursor != oldCursor || scrollOffset != oldScrollOffset
    }

    func cycleSortMode() {
        needsScreenClear = true
        switch sortMode {
        case .stars: sortMode = .name
        case .name: sortMode = .recent
        case .recent: sortMode = .stars
        }
    }

    func cycleFilterMode() {
        // Reset cursor when changing filters
        cursor = 0
        scrollOffset = 0
        needsScreenClear = true

        switch filterMode {
        case .all: filterMode = .selected
        case .selected: filterMode = .downloaded
        case .downloaded: filterMode = .all
        }
    }
}
