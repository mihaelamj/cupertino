import Foundation

/// Text sanitization utilities for TUI
/// Note: Emoji support disabled - current implementation causes box drawing alignment issues
enum TextSanitizer {
    /// Remove emojis from text to prevent display width issues
    static func removeEmojis(from text: String) -> String {
        var result = ""
        for character in text {
            let scalars = character.unicodeScalars
            // Skip if character contains emoji
            let containsEmoji = scalars.contains(where: { scalar in
                scalar.properties.isEmoji || scalar.properties.isEmojiPresentation
            })
            if !containsEmoji {
                result.append(character)
            }
        }
        return result
    }
}
