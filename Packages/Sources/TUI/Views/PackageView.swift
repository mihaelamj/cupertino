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

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += Box.vertical + " \(title)"
        result += String(repeating: " ", count: width - title.count - 3) + Box.vertical + "\r\n"
        result += Box.vertical + " \(stats)"
        result += String(repeating: " ", count: width - stats.count - 3) + Box.vertical + "\r\n"
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

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
            var line = Box.vertical + " \(baseContent)"
            line += String(repeating: " ", count: paddingSize) + stars + " " + Box.vertical

            // Highlight current line
            if isCurrentLine {
                line = Colors.invert + line + Colors.reset
            }

            result += line + "\r\n"
        }

        // Fill remaining space
        let remaining = pageSize - page.count
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
        let help = "↑↓:Navigate  Space:Toggle  s:Sort  /:Search  w:Save  q:Quit"
        result += Box.vertical + " \(help)"
        result += String(repeating: " ", count: width - help.count - 3) + Box.vertical + "\r\n"
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + "\r\n"

        return result
    }

    private func formatStars(_ stars: Int) -> String {
        "⭐ " + NumberFormatter.localizedString(from: NSNumber(value: stars), number: .decimal)
    }
}
