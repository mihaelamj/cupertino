import Foundation

@MainActor
struct ArchiveView {
    func render(
        entries: [ArchiveEntry],
        cursor: Int,
        scrollOffset: Int,
        width: Int,
        height: Int,
        filterCategory: String?,
        searchQuery: String,
        isSearching: Bool,
        statusMessage: String = ""
    ) -> String {
        var result = Colors.reset

        // Enforce minimum terminal size
        let minWidth = 80
        let minHeight = 24

        if width < minWidth || height < minHeight {
            result += Colors.reset
            result += "\r\n\r\n"
            result += "  Terminal too small!\r\n"
            result += "  Minimum size: \(minWidth)x\(minHeight)\r\n"
            result += "  Current size: \(width)x\(height)\r\n"
            result += "\r\n"
            result += "  Please resize your terminal window.\r\n"
            return result
        }

        // Header: 4 lines, Footer: 6 lines (status + help + bottom)
        let pageSize = height - 10
        let page = Array(entries.dropFirst(scrollOffset).prefix(pageSize))

        // Title bar
        let selectedCount = entries.filter(\.isSelected).count
        let downloadedCount = entries.filter(\.isDownloaded).count
        let totalCount = entries.count
        let title = "Apple Archive Documentation Guides"

        // Calculate page numbers
        let currentPage = entries.isEmpty ? 0 : (cursor / pageSize) + 1
        let totalPages = entries.isEmpty ? 0 : (totalCount + pageSize - 1) / pageSize

        // Stats line
        let stats: String
        if isSearching || !searchQuery.isEmpty {
            let searchPrompt = isSearching ? "Search: \(searchQuery)_" : "Search: \(searchQuery)"
            let counts = "Results: \(totalCount)"
            let selection = "Selected: \(selectedCount)"
            stats = String("\(searchPrompt)  \(counts)  \(selection)".prefix(width - 4))
        } else if let category = filterCategory {
            let filterInfo = "Category: \(category)"
            let pageInfo = "Page: \(currentPage)/\(totalPages)  Selected: \(selectedCount)  Downloaded: \(downloadedCount)"
            stats = String("\(filterInfo)  \(pageInfo)".prefix(width - 4))
        } else {
            let pageInfo = "Page: \(currentPage)/\(totalPages)  Total: \(totalCount)  Selected: \(selectedCount)  Downloaded: \(downloadedCount)"
            stats = String(pageInfo.prefix(width - 4))
        }

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width)
        result += renderPaddedLine(stats, width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Archive list
        for (index, entry) in page.enumerated() {
            let absoluteIndex = scrollOffset + index
            let isCurrentLine = absoluteIndex == cursor

            let line = renderArchiveLine(
                entry: entry, width: width, highlight: isCurrentLine, searchQuery: searchQuery
            )
            result += line + "\r\n"
        }

        // Fill remaining space
        let remaining = pageSize - page.count
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Status message line (if any)
        if !statusMessage.isEmpty {
            result += renderPaddedLine(Colors.brightGreen + statusMessage + Colors.reset, width: width)
        } else {
            result += renderPaddedLine("", width: width)
        }

        // Help text
        let help: String
        if isSearching {
            help = "Type to search  Backspace:Delete  Enter/Esc:Exit search  Ctrl+O:Open"
        } else {
            help = "jk/Arrows:Move  Space:Select  w:Save  o:Open  f:Filter  /:Search  h/Esc:Home  q:Quit"
        }
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + Colors.reset + "\r\n"

        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = max(10, width - 4)
        let plainText = stripAnsiCodes(text)
        let sanitized = TextSanitizer.removeEmojis(from: plainText)
        let visibleLength = sanitized.count

        let displayText: String
        if visibleLength > contentWidth {
            let truncated = String(sanitized.prefix(contentWidth - 3))
            displayText = truncated + "..."
        } else {
            displayText = plainText == sanitized ? text : sanitized
        }

        let finalPlainText = stripAnsiCodes(displayText)
        let finalSanitized = TextSanitizer.removeEmojis(from: finalPlainText)
        let padding = max(0, contentWidth - finalSanitized.count)
        return Box.vertical + " " + displayText + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
    }

    private func stripAnsiCodes(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private func renderArchiveLine(entry: ArchiveEntry, width: Int, highlight: Bool, searchQuery: String) -> String {
        // Selection indicator: [R] for required+selected, [*] for selected, [ ] for unselected
        let checkbox: String
        if entry.isRequired {
            checkbox = "[R]" // Required - cannot be deselected
        } else if entry.isSelected {
            checkbox = "[*]"
        } else {
            checkbox = "[ ]"
        }
        // Download indicator: [D] for downloaded
        let downloadIndicator = entry.isDownloaded ? "[D]" : "   "

        // Calculate available width for title
        // Format: "│ [R] [D] Title                    │"
        // width - 4 = content width (for "│ " and " │")
        // checkbox(3) + space(1) + download(3) + space(1) = 8 chars for indicators
        let contentWidth = width - 4
        let indicatorWidth = 8 // "[R] " + "[D] "
        let titleMaxWidth = contentWidth - indicatorWidth

        // Sanitize and truncate title if too long
        let sanitizedTitle = TextSanitizer.removeEmojis(from: entry.title)
        let plainTitle: String
        if sanitizedTitle.count > titleMaxWidth {
            plainTitle = String(sanitizedTitle.prefix(titleMaxWidth - 3)) + "..."
        } else {
            plainTitle = sanitizedTitle
        }

        // Highlight search matches
        let displayTitle: String
        if !searchQuery.isEmpty {
            displayTitle = highlightMatches(in: plainTitle, query: searchQuery, isLineHighlighted: highlight)
        } else {
            displayTitle = plainTitle
        }

        // Calculate padding to fill to end of line
        let plainDisplayTitle = stripAnsiCodes(displayTitle)
        let displayTitleWidth = plainDisplayTitle.count
        let padding = max(0, titleMaxWidth - displayTitleWidth)

        if highlight {
            var line = Colors.bgAppleBlue + Colors.black + Colors.bold
            line += Box.vertical + " " + checkbox + " " + downloadIndicator + " "
            line += displayTitle + Colors.bgAppleBlue + Colors.black + Colors.bold
            line += String(repeating: " ", count: padding) + " "
            line += Colors.reset + Box.vertical
            return line
        } else {
            var line = Box.vertical + " " + checkbox + " " + downloadIndicator + " " + displayTitle
            line += String(repeating: " ", count: padding) + " " + Box.vertical
            return line
        }
    }

    private func highlightMatches(in text: String, query: String, isLineHighlighted: Bool) -> String {
        guard !query.isEmpty else { return text }

        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()
        var result = ""
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let remainingLowercased = String(lowercasedText[currentIndex...])

            if let matchRange = remainingLowercased.range(of: lowercasedQuery) {
                let matchOffset = remainingLowercased.distance(
                    from: remainingLowercased.startIndex, to: matchRange.lowerBound
                )

                let matchStart = text.index(currentIndex, offsetBy: matchOffset)
                let matchEnd = text.index(matchStart, offsetBy: query.count)

                if currentIndex < matchStart {
                    result += String(text[currentIndex..<matchStart])
                }

                if isLineHighlighted {
                    let matchText = String(text[matchStart..<matchEnd])
                    result += Colors.yellow + matchText + Colors.bgAppleBlue + Colors.black + Colors.bold
                } else {
                    let matchText = String(text[matchStart..<matchEnd])
                    result += Colors.bgYellow + Colors.black + matchText + Colors.reset
                }

                currentIndex = matchEnd
            } else {
                result += String(text[currentIndex...])
                break
            }
        }

        return result
    }
}
