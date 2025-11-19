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
        result += Box.bottomRight + "\r\n"

        result += Colors.reset
        return result
    }

    private func renderPaddedLine(_ text: String, width: Int) -> String {
        let contentWidth = width - 4
        let padding = max(0, contentWidth - text.count)
        return Box.vertical + " " + text + String(repeating: " ", count: padding) + " " + Box.vertical + "\r\n"
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

        let line = "  \(setting.label): \(displayValue)\(readOnlyIndicator)"

        let contentWidth = width - 4
        // Account for ANSI codes not taking space
        let lineLength = setting.editable ?
            ("  \(setting.label): \(displayValue)".count) :
            ("  \(setting.label): \(displayValue) [read-only]".count)
        let padding = max(0, contentWidth - lineLength)

        var result = Box.vertical + " " + line + String(repeating: " ", count: padding) + " " + Box.vertical

        if selected, !isEditing {
            result = Colors.bold + Colors.brightCyan + result + Colors.reset
        } else if isEditing {
            result = Colors.bold + Colors.brightYellow + result + Colors.reset
        }

        return result
    }
}
