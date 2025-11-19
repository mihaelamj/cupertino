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
        let stats = "Sort: \(state.sortMode.rawValue)  Selected: \(selectedCount)/\(totalCount)"

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width)
        result += renderPaddedLine(stats, width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Package list
        for (index, entry) in page.enumerated() {
            let absoluteIndex = state.scrollOffset + index
            let isCurrentLine = absoluteIndex == state.cursor

            let line = renderPackageLine(entry: entry, width: width, highlight: isCurrentLine)
            result += line + "\r\n"
        }

        // Fill remaining space
        let remaining = pageSize - page.count
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
        let help = "Arrows/jk:Move  Space:Select  s:Sort  w:Save  q:Quit"
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + "\r\n"

        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = width - 4 // Account for "│ " and " │"
        let padding = max(0, contentWidth - text.count)
        return Box.vertical + " " + text + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
    }

    private func renderPackageLine(entry: PackageEntry, width: Int, highlight: Bool) -> String {
        // Selection indicator: [★] or [ ]
        let checkbox = entry.isSelected ? "[★]" : "[ ]"
        let name = "\(entry.package.owner)/\(entry.package.repo)"
        let starsNum = NumberFormatter.localizedString(from: NSNumber(value: entry.package.stars), number: .decimal)

        // Calculate visible widths (emoji ⭐ = 2 columns, star ★ in checkbox = 1 column)
        let checkboxWidth = 3 // [ ] or [★]
        let starsTextWidth = starsNum.count + 3 // "⭐ " (emoji=2) + number

        // Available space for name
        let contentWidth = width - 4 // "│ " and " │"
        let nameMaxWidth = contentWidth - checkboxWidth - starsTextWidth - 2 // 2 spaces for padding

        // Truncate name if too long
        let truncatedName: String
        if name.count > nameMaxWidth {
            let index = name.index(name.startIndex, offsetBy: nameMaxWidth - 1)
            truncatedName = String(name[..<index]) + "…"
        } else {
            truncatedName = name
        }

        // Build line with exact spacing
        let padding = max(0, nameMaxWidth - truncatedName.count)
        var line = Box.vertical + " " + checkbox + " " + truncatedName
        line += String(repeating: " ", count: padding) + " ⭐ " + starsNum + " " + Box.vertical

        // Highlight current line
        if highlight {
            line = Colors.invert + line + Colors.reset
        }

        return line
    }
}
