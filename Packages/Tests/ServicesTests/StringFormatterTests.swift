import Foundation
@testable import Services
import Testing

// MARK: - String Truncation Tests

@Suite("String Truncation Tests")
struct StringTruncationTests {
    @Test("Truncates long strings with ellipsis")
    func truncatesLongStrings() {
        let long = "This is a very long string that should be truncated"
        let truncated = long.truncated(to: 20)

        #expect(truncated == "This is a very long ...")
        #expect(truncated.count == 23) // 20 + "..."
    }

    @Test("Preserves short strings unchanged")
    func preservesShortStrings() {
        let short = "Short text"
        let result = short.truncated(to: 20)

        #expect(result == "Short text")
    }

    @Test("Trims whitespace before truncating")
    func trimsWhitespace() {
        let padded = "   Padded text   "
        let result = padded.truncated(to: 100)

        #expect(result == "Padded text")
    }

    @Test("Handles exact length match")
    func exactLengthMatch() {
        let exact = "Exactly20Characters!"
        let result = exact.truncated(to: 20)

        #expect(result == "Exactly20Characters!")
    }
}

// MARK: - Markdown Header Escaping Tests

@Suite("Markdown Header Escaping Tests")
struct MarkdownHeaderEscapingTests {
    @Test("Removes inline hash after words: Framework# SwiftUI")
    func removesInlineHashAfterWords() {
        let input = "Framework# SwiftUI"
        let result = input.escapingMarkdownHeaders

        #expect(result == "Framework SwiftUI")
    }

    @Test("Removes multiple inline hashes: Framework## SwiftUI")
    func removesMultipleInlineHashes() {
        let input = "Framework## SwiftUI"
        let result = input.escapingMarkdownHeaders

        #expect(result == "Framework SwiftUI")
    }

    @Test("Removes standalone inline headers: ## [Overview]")
    func removesStandaloneInlineHeaders() {
        let input = "## [Overview]"
        let result = input.escapingMarkdownHeaders

        #expect(result == "[Overview]")
    }

    @Test("Removes triple hash headers: ### Section")
    func removesTripleHashHeaders() {
        let input = "### Section Title"
        let result = input.escapingMarkdownHeaders

        #expect(result == "Section Title")
    }

    @Test("Handles mixed inline and line headers")
    func handlesMixedHeaders() {
        let input = "Framework# SwiftUI\n## Overview\n### Details"
        let result = input.escapingMarkdownHeaders

        #expect(result.contains("Framework SwiftUI"))
        #expect(!result.contains("##"))
        #expect(!result.contains("###"))
    }

    @Test("Collapses multiple consecutive newlines")
    func collapsesMultipleNewlines() {
        let input = "Line 1\n\n\n\nLine 2"
        let result = input.escapingMarkdownHeaders

        #expect(result == "Line 1\n\nLine 2")
    }

    @Test("Handles numbers and plus in word before hash: C++# Language")
    func handlesNumbersAndPlusBeforeHash() {
        let input = "C++# Language"
        let result = input.escapingMarkdownHeaders

        #expect(result == "C++ Language")
    }
}

// MARK: - CamelCase Spacing Tests

@Suite("CamelCase Spacing Tests")
struct CamelCaseSpacingTests {
    @Test("Splits Tabbars -> Tab bars")
    func splitsTabbars() {
        let input = "Tabbars"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Tab bars")
    }

    @Test("Splits Goingfull screen -> Going full screen")
    func splitsGoingfull() {
        let input = "Goingfull screen"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Going full screen")
    }

    @Test("Splits Fullscreen -> Full screen")
    func splitsFullscreen() {
        let input = "Fullscreen"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Full screen")
    }

    @Test("Splits Navigationandsearch -> Navigation and search")
    func splitsNavigationAndSearch() {
        let input = "Navigationandsearch"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Navigation and search")
    }

    @Test("Splits compound controls: Textcontrols -> Text controls")
    func splitsTextControls() {
        let input = "Textcontrols"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Text controls")
    }

    @Test("Splits compound buttons: Actionbuttons -> Action buttons")
    func splitsActionButtons() {
        let input = "Actionbuttons"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Action buttons")
    }

    @Test("Splits compound fields: Textfields -> Text fields")
    func splitsTextFields() {
        let input = "Textfields"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Text fields")
    }

    @Test("Splits compound views: Listviews -> List views")
    func splitsListViews() {
        let input = "Listviews"
        let result = input.addingSpacesToCamelCase

        #expect(result == "List views")
    }

    @Test("Handles voiceover -> Voice over")
    func handlesVoiceOver() {
        let input = "voiceover"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Voice over")
    }

    @Test("Title cases first letter")
    func titleCasesFirstLetter() {
        let input = "lowercase start"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Lowercase start")
    }

    @Test("Trims leading and trailing whitespace")
    func trimsWhitespace() {
        let input = "  Padded bars  "
        let result = input.addingSpacesToCamelCase

        // Double spaces collapsed, then trimmed
        #expect(result == "Padded bars")
    }

    @Test("Case insensitive matching preserves original case")
    func caseInsensitiveMatching() {
        // Patterns match case-insensitively, original case preserved
        let input = "TABBARS"
        let result = input.addingSpacesToCamelCase

        #expect(result == "TAB bars")
    }

    @Test("Handles tables compound: Listsandtables -> Lists and tables")
    func handlesListsAndTables() {
        let input = "Listsandtables"
        let result = input.addingSpacesToCamelCase

        #expect(result == "Lists and tables")
    }
}

// MARK: - Cleaned For Display Tests

@Suite("Cleaned For Display Tests")
struct CleanedForDisplayTests {
    @Test("Removes trailing single hash")
    func removesTrailingSingleHash() {
        let input = "Title#"
        let result = input.cleanedForDisplay

        #expect(result == "Title")
    }

    @Test("Removes trailing double hash")
    func removesTrailingDoubleHash() {
        let input = "Title##"
        let result = input.cleanedForDisplay

        #expect(result == "Title")
    }

    @Test("Removes trailing triple hash")
    func removesTrailingTripleHash() {
        let input = "Title###"
        let result = input.cleanedForDisplay

        #expect(result == "Title")
    }

    @Test("Removes AppleDeveloperDocumentation suffix")
    func removesAppleDeveloperDocSuffix() {
        let input = "Tab bars|AppleDeveloperDocumentation"
        let result = input.cleanedForDisplay

        #expect(result == "Tab bars")
    }

    @Test("Applies CamelCase spacing")
    func appliesCamelCaseSpacing() {
        let input = "Tabbars"
        let result = input.cleanedForDisplay

        #expect(result == "Tab bars")
    }

    @Test("Escapes markdown headers")
    func escapesMarkdownHeaders() {
        let input = "Framework# SwiftUI"
        let result = input.cleanedForDisplay

        #expect(result == "Framework SwiftUI")
    }

    @Test("Handles complex HIG title: Tabbars|AppleDeveloperDocumentation###")
    func handlesComplexHIGTitle() {
        let input = "Tabbars|AppleDeveloperDocumentation###"
        let result = input.cleanedForDisplay

        #expect(result == "Tab bars")
    }

    @Test("Full cleanup: Goingfull screen|AppleDeveloperDocumentation## Overview")
    func fullCleanup() {
        let input = "Goingfull screen|AppleDeveloperDocumentation## Overview"
        let result = input.cleanedForDisplay

        // ## is stripped, brackets weren't in input
        #expect(result == "Going full screen Overview")
    }

    @Test("Trims whitespace and newlines")
    func trimsWhitespaceAndNewlines() {
        let input = "  Title with spaces  \n"
        let result = input.cleanedForDisplay

        #expect(result == "Title with spaces")
    }

    @Test("Preserves clean titles unchanged")
    func preservesCleanTitles() {
        let input = "SwiftUI Button"
        let result = input.cleanedForDisplay

        #expect(result == "SwiftUI Button")
    }
}
