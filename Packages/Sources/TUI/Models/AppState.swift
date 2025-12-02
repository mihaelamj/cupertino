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
    case archive
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

    // Archive state
    var archiveEntries: [ArchiveEntry] = []
    var archiveCursor: Int = 0
    var archiveScrollOffset: Int = 0
    var archiveSearchQuery: String = ""
    var isArchiveSearching: Bool = false
    var archiveFilterCategory: String?
    var archiveStatusMessage: String = ""

    var visiblePackages: [PackageEntry] {
        var filtered = packages

        // Apply search filter (searches owner, repo, description, and language)
        if !searchQuery.isEmpty {
            filtered = filtered.filter { entry in
                entry.package.owner.localizedCaseInsensitiveContains(searchQuery) ||
                    entry.package.repo.localizedCaseInsensitiveContains(searchQuery) ||
                    (entry.package.description ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                    (entry.package.language ?? "").localizedCaseInsensitiveContains(searchQuery)
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

    // MARK: - Archive Methods

    var visibleArchiveEntries: [ArchiveEntry] {
        var filtered = archiveEntries

        // Apply search filter
        if !archiveSearchQuery.isEmpty {
            filtered = filtered.filter { entry in
                entry.title.localizedCaseInsensitiveContains(archiveSearchQuery) ||
                    entry.framework.localizedCaseInsensitiveContains(archiveSearchQuery) ||
                    entry.category.localizedCaseInsensitiveContains(archiveSearchQuery) ||
                    entry.description.localizedCaseInsensitiveContains(archiveSearchQuery)
            }
        }

        // Apply category filter
        if let category = archiveFilterCategory {
            filtered = filtered.filter { $0.category == category }
        }

        return filtered
    }

    func toggleCurrentArchive() {
        let visible = visibleArchiveEntries
        guard archiveCursor < visible.count else { return }

        let entry = visible[archiveCursor]

        // Don't allow deselecting required entries
        if entry.isRequired, entry.isSelected {
            archiveStatusMessage = "Cannot deselect required guide"
            return
        }

        if let index = archiveEntries.firstIndex(where: { $0.path == entry.path }) {
            archiveEntries[index].isSelected.toggle()
        }
    }

    func moveArchiveCursor(delta: Int, pageSize: Int) -> Bool {
        let visible = visibleArchiveEntries
        guard !visible.isEmpty else { return false }

        let oldCursor = archiveCursor
        let oldScrollOffset = archiveScrollOffset

        archiveCursor = max(0, min(archiveCursor + delta, visible.count - 1))

        // Simple scrolling: keep cursor visible
        if archiveCursor >= archiveScrollOffset + pageSize {
            archiveScrollOffset = archiveCursor - pageSize + 1
        } else if archiveCursor < archiveScrollOffset {
            archiveScrollOffset = archiveCursor
        }

        return archiveCursor != oldCursor || archiveScrollOffset != oldScrollOffset
    }

    /// Get unique categories for filtering
    var archiveCategories: [String] {
        Array(Set(archiveEntries.map(\.category))).sorted()
    }

    func cycleArchiveFilterCategory() {
        archiveCursor = 0
        archiveScrollOffset = 0
        needsScreenClear = true

        let categories = archiveCategories
        guard !categories.isEmpty else {
            archiveFilterCategory = nil
            return
        }

        if let current = archiveFilterCategory {
            if let index = categories.firstIndex(of: current) {
                let nextIndex = index + 1
                if nextIndex < categories.count {
                    archiveFilterCategory = categories[nextIndex]
                } else {
                    archiveFilterCategory = nil // cycle back to "all"
                }
            } else {
                archiveFilterCategory = categories.first
            }
        } else {
            archiveFilterCategory = categories.first
        }
    }
}
