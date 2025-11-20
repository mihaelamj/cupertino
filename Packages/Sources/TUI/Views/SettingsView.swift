import Foundation
import Shared

struct SettingItem {
    let label: String
    let value: String
    let editable: Bool
}

struct SettingsView {
    func render(cursor: Int, width: Int, height: Int, baseDirectory: String, isEditing: Bool, editBuffer: String, statusMessage: String = "") -> String {
        var result = Colors.reset

        let title = "Settings"

        let settings = [
            SettingItem(label: "Base Directory", value: baseDirectory, editable: true),
            SettingItem(label: "Docs Directory", value: "docs", editable: false),
            SettingItem(label: "Swift Evolution", value: "swift-evolution", editable: false),
            SettingItem(label: "Swift.org", value: "swift-org", editable: false),
            SettingItem(label: "Swift Book", value: "swift-book", editable: false),
            SettingItem(label: "Packages", value: "packages", editable: false),
            SettingItem(label: "Sample Code", value: "sample-code", editable: false),
        ]

        result += Box.topLeft + String(repeating: Box.horizontal, count: width - 2) + Box.topRight + "\r\n"
        result += renderPaddedLine(title, width: width)

        if !statusMessage.isEmpty {
            result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
            result += renderPaddedLine(statusMessage, width: width)
        }

        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"

        result += renderPaddedLine("", width: width)
        result += renderPaddedLine("Directory Structure:", width: width)
        result += renderPaddedLine("", width: width)

        for (index, setting) in settings.enumerated() {
            let isSelected = index == cursor
            let isEditingThisItem = isEditing && isSelected && setting.editable
            let line = renderSettingLine(
                setting: setting,
                width: width,
                selected: isSelected,
                isEditing: isEditingThisItem,
                editBuffer: editBuffer
            )
            result += line + "\r\n"
        }

        // Fill space
        let usedLines = 6 + settings.count
        let remaining = height - usedLines - 2
        for _ in 0..<remaining {
            result += Box.vertical + String(repeating: " ", count: width - 2) + Box.vertical + "\r\n"
        }

        // Footer
        result += Box.teeRight + String(repeating: Box.horizontal, count: width - 2) + Box.teeLeft + "\r\n"
        let help = isEditing
            ? "Enter:Save  Esc:Cancel"
            : "e:Edit  Esc/h:Home  q:Quit"
        result += renderPaddedLine(help, width: width)
        result += Box.bottomLeft + String(repeating: Box.horizontal, count: width - 2)
        result += Box.bottomRight + Colors.reset + "\r\n"

        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = width - 4
        let sanitized = TextSanitizer.removeEmojis(from: text)

        // Truncate if too long
        let displayText: String
        if sanitized.count > contentWidth {
            displayText = String(sanitized.prefix(contentWidth - 1)) + "…"
        } else {
            displayText = text == sanitized ? text : sanitized
        }

        let finalSanitized = TextSanitizer.removeEmojis(from: displayText)
        let padding = max(0, contentWidth - finalSanitized.count)
        return Box.vertical + " " + displayText + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
    }

    private func renderSettingLine(
        setting: SettingItem,
        width: Int,
        selected: Bool,
        isEditing: Bool,
        editBuffer: String
    ) -> String {
        let readOnlyIndicator = setting.editable ? "" : " " + Colors.dim + "[read-only]" + Colors.reset
        let displayValue = isEditing ? editBuffer + "█" : setting.value

        let contentWidth = width - 4

        // Build plain version for width calculation
        let plainLine = setting.editable ?
            "  \(setting.label): \(displayValue)" :
            "  \(setting.label): \(displayValue) [read-only]"
        let sanitizedLine = TextSanitizer.removeEmojis(from: plainLine)

        // Truncate if necessary
        let line: String
        if sanitizedLine.count > contentWidth {
            let truncatedPlain = String(sanitizedLine.prefix(contentWidth - 1)) + "…"
            line = truncatedPlain // Use truncated plain text
        } else {
            line = "  \(setting.label): \(displayValue)\(readOnlyIndicator)"
        }

        let finalSanitized = TextSanitizer.removeEmojis(from: line.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression))
        let padding = max(0, contentWidth - finalSanitized.count)

        var result = Box.vertical + " " + line + String(repeating: " ", count: padding) + " " + Box.vertical

        if selected, !isEditing {
            result = Colors.bgAppleBlue + Colors.black + result + Colors.reset
        } else if isEditing {
            result = Colors.bgAppleOrange + Colors.black + result + Colors.reset
        }

        return result
    }
}
