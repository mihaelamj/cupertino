import Core
import Foundation

final class AppState {
    var packages: [PackageEntry] = []
    var cursor: Int = 0
    var scrollOffset: Int = 0
    var sortMode: SortMode = .stars
    var searchQuery: String = ""
    var showOnlySelected: Bool = false
    var statusMessage: String = ""

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

        // Apply selection filter
        if showOnlySelected {
            filtered = filtered.filter(\.isSelected)
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
}
