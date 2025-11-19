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
            MenuItem(key: "1", icon: "📦", title: "Packages", subtitle: "Browse \(stats.totalPackages) Swift packages"),
            MenuItem(key: "2", icon: "📚", title: "Library", subtitle: "\(stats.artifactCount) artifact collections"),
            MenuItem(key: "3", icon: "⚙️", title: "Settings", subtitle: "Configure Cupertino"),
        ]

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width, center: true)
        result += renderPaddedLine(subtitle, width: width, center: true)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Stats section
        result += renderPaddedLine("", width: width)
        result += renderPaddedLine("📊 Quick Stats", width: width)
        result += renderPaddedLine("", width: width)
        result += renderPaddedLine("  • \(stats.selectedPackages) packages selected", width: width)
        result += renderPaddedLine("  • \(stats.downloadedPackages) packages downloaded", width: width)
        result += renderPaddedLine("  • \(formatBytes(stats.totalSize)) total storage", width: width)
        result += renderPaddedLine("", width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Menu
        result += renderPaddedLine("", width: width)
        result += renderPaddedLine("Select a view:", width: width)
        result += renderPaddedLine("", width: width)

        for (index, item) in menuItems.enumerated() {
            let isSelected = index == cursor
            let line = renderMenuItem(item: item, width: width, selected: isSelected)
            result += line + "\r\n"
        }

        // Fill space
        let usedLines = 16 // approximate
        let remaining = height - usedLines - 2
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
        let help = "↑↓/jk:Navigate  Enter/1-3:Select  q:Quit"
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + "\r\n"

        result += Colors.reset
        return result
    }

    private func renderPaddedLine(_ text: String, width: Int, center: Bool = false) -> String {
        let contentWidth = width - 4
        if center {
            let padding = max(0, contentWidth - text.count)
            let leftPad = padding / 2
            let rightPad = padding - leftPad
            return Box.vertical + " " + String(repeating: " ", count: leftPad) + text + String(repeating: " ", count: rightPad) + " " + Box.vertical + "\r\n"
        } else {
            let padding = max(0, contentWidth - text.count)
            return Box.vertical + " " + text + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
        }
    }

    private func renderMenuItem(item: MenuItem, width: Int, selected: Bool) -> String {
        let prefix = selected ? "▶ " : "  "
        let line = "\(prefix)\(item.icon)  \(item.key). \(item.title) - \(item.subtitle)"

        let contentWidth = width - 4
        let padding = max(0, contentWidth - line.count)

        var result = Box.vertical + " " + line + String(repeating: " ", count: padding) + " " + Box.vertical

        if selected {
            result = Colors.bold + Colors.brightCyan + result + Colors.reset
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
    let totalSize: Int64
}
