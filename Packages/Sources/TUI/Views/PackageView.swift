import Core
import Foundation

struct PackageView {
    func render(state: AppState, width: Int, height: Int) -> String {
        // Always start with a reset to clear any lingering ANSI codes
        var result = Colors.reset
        let visible = state.visiblePackages
        let pageSize = height - 4 // Account for header & footer
        let page = Array(visible.dropFirst(state.scrollOffset).prefix(pageSize))

        // Title bar
        let selectedCount = state.packages.filter(\.isSelected).count
        let totalCount = state.packages.count
        let visibleCount = visible.count
        let title = "Swift Packages Curator"

        // Show search query and result count if searching
        let stats: String
        if state.isSearching || !state.searchQuery.isEmpty {
            let searchPrompt = state.isSearching ? "Search: \(state.searchQuery)_" : "Search: \(state.searchQuery)"
            stats = "\(searchPrompt)  Results: \(visibleCount)/\(totalCount)  Selected: \(selectedCount)"
        } else {
            stats = "Sort: \(state.sortMode.rawValue)  Selected: \(selectedCount)/\(totalCount)"
        }

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width)
        result += renderPaddedLine(stats, width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Package list
        for (index, entry) in page.enumerated() {
            let absoluteIndex = state.scrollOffset + index
            let isCurrentLine = absoluteIndex == state.cursor

            let line = renderPackageLine(entry: entry, width: width, highlight: isCurrentLine, searchQuery: state.searchQuery)
            result += line + "\r\n"
        }

        // Fill remaining space
        let remaining = pageSize - page.count
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
        let help: String
        if state.isSearching {
            help = "Type to search  Backspace:Delete  Enter/Esc:Exit search"
        } else {
            help = "↑↓/jk:Move  ←→:Page  Space:Select  o/Enter:Open  s:Sort  /:Search  w:Save  q:Quit"
        }
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + "\r\n"

        // Always end with a reset to ensure clean state
        result += Colors.reset

        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = width - 4 // Account for "│ " and " │"
        let padding = max(0, contentWidth - text.count)
        return Box.vertical + " " + text + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
    }

    private func renderPackageLine(entry: PackageEntry, width: Int, highlight: Bool, searchQuery: String) -> String {
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
        let plainName: String
        if name.count > nameMaxWidth {
            let index = name.index(name.startIndex, offsetBy: nameMaxWidth - 1)
            plainName = String(name[..<index]) + "…"
        } else {
            plainName = name
        }

        // Highlight search matches
        let displayName: String
        if !searchQuery.isEmpty {
            displayName = highlightMatches(in: plainName, query: searchQuery)
        } else {
            displayName = plainName
        }

        // Build line with exact spacing (using plain name for width calculation)
        let padding = max(0, nameMaxWidth - plainName.count)
        var line = Box.vertical + " " + checkbox + " " + displayName
        line += String(repeating: " ", count: padding) + " ⭐ " + starsNum + " " + Box.vertical

        // Highlight current line
        if highlight {
            line = Colors.invert + line + Colors.reset
        }

        return line
    }

    private func highlightMatches(in text: String, query: String) -> String {
        guard !query.isEmpty else { return text }

        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()
        var result = ""
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            // Search in the remaining lowercase text
            let remainingLowercased = String(lowercasedText[currentIndex...])

            if let matchRange = remainingLowercased.range(of: lowercasedQuery) {
                // Calculate offset from start of remaining text
                let matchOffset = remainingLowercased.distance(from: remainingLowercased.startIndex, to: matchRange.lowerBound)

                // Calculate actual indices in original text
                let matchStart = text.index(currentIndex, offsetBy: matchOffset)
                let matchEnd = text.index(matchStart, offsetBy: query.count)

                // Add text before match
                if currentIndex < matchStart {
                    result += String(text[currentIndex..<matchStart])
                }

                // Add highlighted match
                result += Colors.bold + Colors.brightYellow + String(text[matchStart..<matchEnd]) + Colors.reset

                // Move past the match
                currentIndex = matchEnd
            } else {
                // No more matches, add remaining text
                result += String(text[currentIndex...])
                break
            }
        }

        return result
    }
}
