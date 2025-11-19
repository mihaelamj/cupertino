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

    var visiblePackages: [PackageEntry] {
        var filtered = packages

        // Apply search filter
        if !searchQuery.isEmpty {
            filtered = filtered.filter { entry in
                entry.package.owner.localizedCaseInsensitiveContains(searchQuery) ||
                    entry.package.repo.localizedCaseInsensitiveContains(searchQuery) ||
                    entry.package.description?.localizedCaseInsensitiveContains(searchQuery) == true
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

    func moveCursor(delta: Int, pageSize: Int) {
        let visible = visiblePackages
        guard !visible.isEmpty else { return }

        cursor = max(0, min(cursor + delta, visible.count - 1))

        // Auto-scroll
        if cursor < scrollOffset {
            scrollOffset = cursor
        } else if cursor >= scrollOffset + pageSize {
            scrollOffset = cursor - pageSize + 1
        }
    }

    func cycleSortMode() {
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

        switch filterMode {
        case .all: filterMode = .selected
        case .selected: filterMode = .downloaded
        case .downloaded: filterMode = .all
        }
    }
}
