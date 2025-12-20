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
        result += Box.bottomRight + Colors.reset + "\r\n"

        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = width - 4
        let sanitized = TextSanitizer.removeEmojis(from: text)
        let padding = max(0, contentWidth - sanitized.count)
        let displayText = text == sanitized ? text : sanitized
        return Box.vertical + " " + displayText + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
    }

    private func renderArtifactLine(artifact: ArtifactInfo, width: Int, highlight: Bool) -> String {
        let icon = "*"
        let name = artifact.name
        let itemsText = "\(artifact.itemCount) items"
        let sizeText = Shared.Formatting.formatBytes(artifact.sizeBytes)

        // Calculate widths (no emojis)
        let iconWidth = icon.count
        let itemsWidth = itemsText.count
        let sizeWidth = sizeText.count
        let contentWidth = width - 4

        let nameMaxWidth = contentWidth - iconWidth - itemsWidth - sizeWidth - 4 // spaces for padding

        // Sanitize and truncate name if needed
        let sanitizedName = TextSanitizer.removeEmojis(from: name)
        let displayName: String
        if sanitizedName.count > nameMaxWidth {
            displayName = String(sanitizedName.prefix(nameMaxWidth - 1)) + "…"
        } else {
            displayName = sanitizedName
        }

        let padding = max(0, nameMaxWidth - displayName.count)
        var line = Box.vertical + " " + icon + " " + displayName
        line += String(repeating: " ", count: padding) + " " + itemsText + "  " + sizeText + " " + Box.vertical

        if highlight {
            line = Colors.bgAppleBlue + Colors.black + line + Colors.reset
        }

        return line
    }
}
