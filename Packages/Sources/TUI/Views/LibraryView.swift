import Foundation
import Shared

struct ArtifactInfo {
    let name: String
    let path: URL
    let itemCount: Int
    let sizeBytes: Int64
}

struct LibraryView {
    func render(artifacts: [ArtifactInfo], cursor: Int, width: Int, height: Int) -> String {
        var result = Colors.reset
        let pageSize = height - 4
        let page = Array(artifacts.prefix(pageSize))

        // Title bar
        let title = "Cupertino Library"
        let stats = "Total artifacts: \(artifacts.count)"

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width)
        result += renderPaddedLine(stats, width: width)
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        // Artifact list
        for (index, artifact) in page.enumerated() {
            let isCurrentLine = index == cursor
            let line = renderArtifactLine(artifact: artifact, width: width, highlight: isCurrentLine)
            result += line + "\r\n"
        }

        // Fill remaining space
        let remaining = pageSize - page.count
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
        let help = "↑↓/jk:Move  Enter/o:Open  Tab:Packages  q:Quit"
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + "\r\n"

        result += Colors.reset
        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = width - 4
        let padding = max(0, contentWidth - text.count)
        return Box.vertical + " " + text + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
    }

    private func renderArtifactLine(artifact: ArtifactInfo, width: Int, highlight: Bool) -> String {
        let icon = "📚"
        let name = artifact.name
        let itemsText = "\(artifact.itemCount) items"
        let sizeText = formatBytes(artifact.sizeBytes)

        // Calculate widths
        let iconWidth = 2
        let itemsWidth = itemsText.count
        let sizeWidth = sizeText.count
        let contentWidth = width - 4

        let nameMaxWidth = contentWidth - iconWidth - itemsWidth - sizeWidth - 4 // spaces for padding

        // Truncate name if needed
        let displayName: String
        if name.count > nameMaxWidth {
            let index = name.index(name.startIndex, offsetBy: nameMaxWidth - 1)
            displayName = String(name[..<index]) + "…"
        } else {
            displayName = name
        }

        let padding = max(0, nameMaxWidth - displayName.count)
        var line = Box.vertical + " " + icon + " " + displayName
        line += String(repeating: " ", count: padding) + " " + itemsText + "  " + sizeText + " " + Box.vertical

        if highlight {
            line = Colors.invert + line + Colors.reset
        }

        return line
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
