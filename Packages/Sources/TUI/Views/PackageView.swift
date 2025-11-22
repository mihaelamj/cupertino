import Core
import Foundation

@MainActor
struct PackageView {
    func render(state: AppState, width: Int, height: Int) -> String {
        // Always start with a reset to clear any lingering ANSI codes
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

        let visible = state.visiblePackages
        // Header: 4 lines, Footer: 7 lines (separator + pkg name + desc + metadata + separator + help + bottom)
        let pageSize = height - 11
        let page = Array(visible.dropFirst(state.scrollOffset).prefix(pageSize))

        // Title bar
        let selectedCount = state.packages.filter(\.isSelected).count
        let totalCount = state.packages.count
        let visibleCount = visible.count
        let title = "Swift Packages Curator"

        // Calculate page numbers
        let currentPage = visible.isEmpty ? 0 : (state.cursor / pageSize) + 1
        let totalPages = visible.isEmpty ? 0 : (visibleCount + pageSize - 1) / pageSize

        // Stats line - ensure it fits within width
        let stats: String
        if state.isSearching || !state.searchQuery.isEmpty {
            let searchPrompt = state.isSearching ? "Search: \(state.searchQuery)_" : "Search: \(state.searchQuery)"
            let counts = "Results: \(visibleCount)/\(totalCount)"
            let pagination = "Page: \(currentPage)/\(totalPages)"
            let selection = "Selected: \(selectedCount)"
            let results = "\(counts)  \(pagination)  \(selection)"
            let fullStats = "\(searchPrompt)  \(results)"
            stats = String(fullStats.prefix(width - 4))
        } else {
            let filterSort = "Filter: \(state.filterMode.rawValue)  Sort: \(state.sortMode.rawValue)"
            let pageInfo = "Page: \(currentPage)/\(totalPages)  Selected: \(selectedCount)/\(totalCount)"
            let fullStats = "\(filterSort)  \(pageInfo)"
            stats = String(fullStats.prefix(width - 4))
        }

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width)
        result += renderPaddedLine(stats, width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Package list
        for (index, entry) in page.enumerated() {
            let absoluteIndex = state.scrollOffset + index
            let isCurrentLine = absoluteIndex == state.cursor

            let line = renderPackageLine(
                entry: entry, width: width, highlight: isCurrentLine, searchQuery: state.searchQuery
            )
            result += line + "\r\n"
        }

        // Fill remaining space
        let remaining = pageSize - page.count
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer with current package info
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Show current package details with metadata
        if !visible.isEmpty, state.cursor < visible.count {
            let currentPkg = visible[state.cursor].package
            let pkgInfo = "\(currentPkg.owner)/\(currentPkg.repo)"

            // Show page info: "Showing 1-20 of 150" or "Showing 1-5 of 5 (filtered)"
            let startIdx = state.scrollOffset + 1
            let endIdx = min(state.scrollOffset + pageSize, visible.count)
            let pageInfo = visible.count < totalCount ?
                " [\(startIdx)-\(endIdx)/\(visible.count) filtered from \(totalCount)]" :
                " [\(startIdx)-\(endIdx)/\(totalCount)]"

            // Build metadata line (License • Updated)
            var metadata: [String] = []
            if let license = currentPkg.license {
                metadata.append(license)
            }
            if let updated = currentPkg.updatedAt {
                // Parse ISO date and format as relative time
                let updatedStr = formatRelativeDate(updated)
                metadata.append("Updated \(updatedStr)")
            }
            let metadataLine = metadata.isEmpty ? "" : Colors.gray + metadata.joined(separator: " • ") + Colors.reset

            let desc = currentPkg.description ?? "No description"

            result += renderPaddedLine(Colors.brightCyan + pkgInfo + Colors.reset + pageInfo, width: width)
            result += renderPaddedLine(desc, width: width)
            if !metadataLine.isEmpty {
                result += renderPaddedLine(metadataLine, width: width)
            }
        } else {
            result += renderPaddedLine("", width: width)
            result += renderPaddedLine("", width: width)
            result += renderPaddedLine("", width: width)
        }

        // Separator line before help
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Help text (minimum 80 width guaranteed)
        let help: String
        if state.isSearching {
            help = "↑↓/jk:Navigate  Ctrl+O:Open  Type to search  Backspace:Delete  Enter/Esc:Exit search"
        } else {
            help = "↑↓/jk:Move  Space:Select  o:Open  f:Filter  s:Sort  /:Search  w:Save  h/Esc:Home  q:Quit"
        }
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + Colors.reset + "\r\n"

        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = max(10, width - 4) // Account for "│ " and " │", minimum 10 chars
        // Strip ANSI codes and remove emojis
        let plainText = stripAnsiCodes(text)
        let sanitized = TextSanitizer.removeEmojis(from: plainText)
        let visibleLength = sanitized.count

        // Truncate if text is too long for the available width
        let displayText: String
        if visibleLength > contentWidth {
            let truncated = String(sanitized.prefix(contentWidth - 3))
            displayText = truncated + "..."
        } else {
            // Use sanitized text if original had emojis
            displayText = plainText == sanitized ? text : sanitized
        }

        let finalPlainText = stripAnsiCodes(displayText)
        let finalSanitized = TextSanitizer.removeEmojis(from: finalPlainText)
        let padding = max(0, contentWidth - finalSanitized.count)
        return Box.vertical + " " + displayText + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
    }

    /// Strip ANSI escape codes from a string to get visible character count
    private func stripAnsiCodes(_ text: String) -> String {
        // Remove ANSI escape sequences: \u{001B}[...m
        text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private func renderPackageLine(entry: PackageEntry, width: Int, highlight: Bool, searchQuery: String) -> String {
        // Selection indicator: [*] or [ ]
        let checkbox = entry.isSelected ? "[*]" : "[ ]"
        // Download indicator: [D] for downloaded packages
        let downloadIndicator = entry.isDownloaded ? "[D]" : "   "
        let name = "\(entry.package.owner)/\(entry.package.repo)"
        let starsNum = NumberFormatter.localizedString(from: NSNumber(value: entry.package.stars), number: .decimal)

        // Calculate visible widths (no emojis)
        let checkboxWidth = checkbox.count
        let downloadWidth = downloadIndicator.count
        let starsTextWidth = starsNum.count

        // Available space for name
        let contentWidth = width - 4 // "│ " and " │"
        // Fixed components: checkbox(3) + download(3) + " * "(3) + spaces(2) = 11 + starsTextWidth
        // Spaces: (1) after checkbox, (1) after download
        // Note: spaces in "│ " and " │" are already subtracted in contentWidth
        // 3 for " * ", 2 for spaces after checkbox and download
        let nameMaxWidth = contentWidth - checkboxWidth - downloadWidth - starsTextWidth - 3 - 2

        // Sanitize and truncate name if too long
        let sanitizedName = TextSanitizer.removeEmojis(from: name)
        let plainName: String
        if sanitizedName.count > nameMaxWidth {
            plainName = String(sanitizedName.prefix(nameMaxWidth - 1)) + "…"
        } else {
            plainName = sanitizedName
        }

        // Highlight search matches (pass highlight flag to adjust colors)
        let displayName: String
        if !searchQuery.isEmpty {
            displayName = highlightMatches(in: plainName, query: searchQuery, isLineHighlighted: highlight)
        } else {
            displayName = plainName
        }

        // Build line with exact spacing
        let plainDisplayName = stripAnsiCodes(displayName)
        let displayNameWidth = plainDisplayName.count
        let padding = max(0, nameMaxWidth - displayNameWidth)

        // Highlight current line with cyan background, black text, and bold
        if highlight {
            // Apply background to entire line, resetting after each component to avoid conflicts
            var line = Colors.bgAppleBlue + Colors.black + Colors.bold
            line += Box.vertical + " " + checkbox + " " + downloadIndicator + " "
            // Re-apply after displayName (which may have its own colors)
            line += displayName + Colors.bgAppleBlue + Colors.black + Colors.bold
            line += String(repeating: " ", count: padding) + " * " + starsNum + " "
            line += Colors.reset + Box.vertical
            return line
        } else {
            var line = Box.vertical + " " + checkbox + " " + downloadIndicator + " " + displayName
            line += String(repeating: " ", count: padding) + " * " + starsNum + " " + Box.vertical
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
            // Search in the remaining lowercase text
            let remainingLowercased = String(lowercasedText[currentIndex...])

            if let matchRange = remainingLowercased.range(of: lowercasedQuery) {
                // Calculate offset from start of remaining text
                let matchOffset = remainingLowercased.distance(
                    from: remainingLowercased.startIndex, to: matchRange.lowerBound
                )

                // Calculate actual indices in original text
                let matchStart = text.index(currentIndex, offsetBy: matchOffset)
                let matchEnd = text.index(matchStart, offsetBy: query.count)

                // Add text before match
                if currentIndex < matchStart {
                    result += String(text[currentIndex..<matchStart])
                }

                // Add highlighted match
                // When line is highlighted (blue bg), use yellow text on blue background
                // When line is not highlighted, use yellow background with black text
                if isLineHighlighted {
                    let matchText = String(text[matchStart..<matchEnd])
                    result += Colors.yellow + matchText + Colors.bgAppleBlue + Colors.black + Colors.bold
                } else {
                    let matchText = String(text[matchStart..<matchEnd])
                    result += Colors.bgYellow + Colors.black + matchText + Colors.reset
                }

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

    /// Format ISO8601 date string to relative time (e.g., "2 months ago")
    private func formatRelativeDate(_ isoDateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoDateString) else {
            return isoDateString
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)
        let days = Int(interval / 86400)

        if days < 1 {
            return "today"
        } else if days < 7 {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if days < 30 {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if days < 365 {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else {
            let years = days / 365
            return "\(years) year\(years == 1 ? "" : "s") ago"
        }
    }
}
