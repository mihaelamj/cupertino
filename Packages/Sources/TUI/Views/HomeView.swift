import Foundation

struct MenuItem {
    let key: String
    let icon: String
    let title: String
    let subtitle: String
}

struct HomeView {
    func render(cursor: Int, width: Int, height: Int, stats: HomeStats) -> String {
        var result = Colors.reset

        let title = "Cupertino Documentation Manager"
        let subtitle = "Navigate Apple & Swift documentation offline"

        // Menu items
        let menuItems = [
            MenuItem(key: "1", icon: "*", title: "Packages", subtitle: "Browse \(stats.totalPackages) Swift packages"),
            MenuItem(key: "2", icon: "*", title: "Library", subtitle: "\(stats.artifactCount) artifact collections"),
            MenuItem(key: "3", icon: "*", title: "Archive", subtitle: "\(stats.archiveGuideCount) classic Apple guides"),
            MenuItem(key: "4", icon: "*", title: "Settings", subtitle: "Configure Cupertino"),
        ]

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width, center: true)
        result += renderPaddedLine(subtitle, width: width, center: true)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Stats section - compact
        result += renderPaddedLine("Quick Stats", width: width)
        let selected = " \(stats.selectedPackages) pkgs"
        let downloaded = " \(stats.downloadedPackages) dl"
        let totalSize = " \(formatBytes(stats.totalSize))"
        let statsLine = "•\(selected) •\(downloaded) •\(totalSize)"
        result += renderPaddedLine(statsLine, width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Quick Commands section
        result += renderPaddedLine("Quick Commands:", width: width)
        result += renderPaddedLine("  cupertino fetch --type package-docs", width: width)
        result += renderPaddedLine("  cupertino fetch --type archive", width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Menu - compact
        result += renderPaddedLine("Select a view:", width: width)

        for (index, item) in menuItems.enumerated() {
            let isSelected = index == cursor
            let line = renderMenuItem(item: item, width: width, selected: isSelected)
            result += line + "\r\n"
        }

        // Fill remaining space
        // Count actual lines used:
        // 1: top border
        // 2: title + subtitle
        // 1: separator
        // 2: stats (header + compact line)
        // 1: separator
        // 3: quick commands (header + 2 commands)
        // 1: separator
        // 1: "Select a view"
        // 4: menu items (packages, library, archive, settings)
        // 1: separator (below)
        // 1: help
        // 1: bottom border
        // Total: 19 lines
        let usedLines = 19
        let remaining = max(0, height - usedLines)
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
        let help = "↑↓/jk:Navigate  Enter/1-3:Select  q:Quit"
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + Colors.reset + "\r\n"

        return result
    }

    private func renderPaddedLine(_ text: String, width: Int, center: Bool = false) -> String {
        let contentWidth = width - 4
        if center {
            let padding = max(0, contentWidth - text.count)
            let leftPad = padding / 2
            let rightPad = padding - leftPad
            let leftSpacing = String(repeating: " ", count: leftPad)
            let rightSpacing = String(repeating: " ", count: rightPad)
            return Box.vertical + " " + leftSpacing + text + rightSpacing + " " + Box.vertical + "\r\n"
        } else {
            let padding = max(0, contentWidth - text.count)
            return Box.vertical + " " + text + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
        }
    }

    private func renderMenuItem(item: MenuItem, width: Int, selected: Bool) -> String {
        let prefix = selected ? "> " : "  "
        let line = "\(prefix)\(item.icon) \(item.key). \(item.title) - \(item.subtitle)"

        let contentWidth = width - 4
        let padding = max(0, contentWidth - line.count)

        var result = Box.vertical + " " + line + String(repeating: " ", count: padding) + " " + Box.vertical

        if selected {
            result = Colors.bgAppleBlue + Colors.black + result + Colors.reset
        }

        return result
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kilobytes = Double(bytes) / 1024
        let megabytes = kilobytes / 1024
        let gigabytes = megabytes / 1024

        if gigabytes >= 1 {
            return String(format: "%.1f GB", gigabytes)
        } else if megabytes >= 1 {
            return String(format: "%.1f MB", megabytes)
        } else if kilobytes >= 1 {
            return String(format: "%.0f KB", kilobytes)
        } else {
            return "\(bytes) B"
        }
    }
}

struct HomeStats {
    let totalPackages: Int
    let selectedPackages: Int
    let downloadedPackages: Int
    let artifactCount: Int
    let archiveGuideCount: Int
    let totalSize: Int64
}
