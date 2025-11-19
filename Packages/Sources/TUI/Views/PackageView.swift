import Core
import Foundation

struct PackageView {
    func render(state: AppState, width: Int, height: Int) -> String {
        var result = ""
        let visible = state.visiblePackages
        let pageSize = height - 4 // Account for header & footer
        let page = Array(visible.dropFirst(state.scrollOffset).prefix(pageSize))

        // Title bar
        let selectedCount = state.packages.filter(\.isSelected).count
        let totalCount = state.packages.count
        let title = "Swift Packages Curator"
        let stats = "Sort: \(state.sortMode.rawValue)     Selected: \(selectedCount)/\(totalCount)"

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\n"
        result += Box.vertical + " \(title)" + String(repeating: " ", count: width - title.count - 3) + Box.vertical + "\n"
        result += Box.vertical + " \(stats)" + String(repeating: " ", count: width - stats.count - 3) + Box.vertical + "\n"
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\n"

        // Package list
        for (index, entry) in page.enumerated() {
            let absoluteIndex = state.scrollOffset + index
            let isCurrentLine = absoluteIndex == state.cursor

            // Selection indicator
            let checkbox = entry.isSelected ? "[" + Colors.selected + "]" : "[ ]"
            let name = "\(entry.package.owner)/\(entry.package.repo)"
            let stars = formatStars(entry.package.stars)

            // Build line with proper spacing
            let baseContent = "\(checkbox) \(name)"
            let paddingSize = max(1, width - baseContent.count - stars.count - 10)
            var line = Box.vertical + " \(baseContent)" + String(repeating: " ", count: paddingSize) + stars + " " + Box.vertical

            // Highlight current line
            if isCurrentLine {
                line = Colors.invert + line + Colors.reset
            }

            result += line + "\n"
        }

        // Fill remaining space
        let remaining = pageSize - page.count
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\n"
        let help = "↑↓:Navigate  Space:Toggle  s:Sort  /:Search  w:Save  q:Quit"
        result += Box.vertical + " \(help)" + String(repeating: " ", count: width - help.count - 3) + Box.vertical + "\n"
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2) + Box.bottomRight + "\n"

        return result
    }

    private func formatStars(_ stars: Int) -> String {
        "⭐ " + NumberFormatter.localizedString(from: NSNumber(value: stars), number: .decimal)
    }
}
