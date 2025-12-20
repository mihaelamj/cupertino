import Foundation
import Search
import Shared

// MARK: - Result Formatter Protocol

/// Protocol for formatting search results to different output formats
public protocol ResultFormatter {
    associatedtype Input
    func format(_ input: Input) -> String
}

// MARK: - Search Result Format Configuration

/// Configuration for search result formatting
public struct SearchResultFormatConfig: Sendable {
    public let showScore: Bool
    public let showWordCount: Bool
    public let showSource: Bool
    public let showAvailability: Bool
    public let showSeparators: Bool
    public let emptyMessage: String

    public init(
        showScore: Bool = false,
        showWordCount: Bool = false,
        showSource: Bool = true,
        showAvailability: Bool = false,
        showSeparators: Bool = false,
        emptyMessage: String = "No results found"
    ) {
        self.showScore = showScore
        self.showWordCount = showWordCount
        self.showSource = showSource
        self.showAvailability = showAvailability
        self.showSeparators = showSeparators
        self.emptyMessage = emptyMessage
    }

    /// Shared configuration for both CLI and MCP markdown output (identical results)
    public static let shared = SearchResultFormatConfig(
        showScore: true,
        showWordCount: true,
        showSource: false,
        showAvailability: true,
        showSeparators: true,
        emptyMessage: "_No results found. Try broader search terms._"
    )

    /// Alias for CLI (uses shared config for identical output)
    public static let cliDefault = shared

    /// Alias for MCP (uses shared config for identical output)
    public static let mcpDefault = shared
}

// MARK: - String Utilities

public extension String {
    /// Truncates the string to a maximum length, adding "..." if truncated
    func truncated(to maxLength: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "..."
    }

    /// Cleans up display artifacts from content
    /// - Removes trailing markdown headers (###)
    /// - Removes |AppleDeveloperDocumentation suffix from HIG titles
    /// - Adds spaces to camelCase HIG titles (Tabbars → Tab bars)
    /// - Escapes markdown headers that would break document structure
    /// - Trims whitespace
    var cleanedForDisplay: String {
        var result = self

        // Remove trailing ### (markdown artifacts)
        while result.hasSuffix("###") || result.hasSuffix("##") || result.hasSuffix("#") {
            result = String(result.dropLast(result.hasSuffix("###") ? 3 : (result.hasSuffix("##") ? 2 : 1)))
        }

        // Remove |AppleDeveloperDocumentation suffix from HIG titles
        if result.contains("|AppleDeveloperDocumentation") {
            result = result.replacingOccurrences(of: "|AppleDeveloperDocumentation", with: "")
        }

        // Always apply pattern fixes for concatenated words (Tabbars → Tab bars, Goingfull → Going full)
        result = result.addingSpacesToCamelCase

        // Escape markdown headers that would break document structure
        // Replace # at start of lines with escaped version
        result = result.escapingMarkdownHeaders

        // Clean up any remaining artifacts
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Strips markdown headers and cleans up formatting artifacts
    var escapingMarkdownHeaders: String {
        var result = self

        // Remove inline markdown headers (e.g., "Framework# SwiftUI" -> "Framework SwiftUI")
        // This handles cases where # appears after a word (from collapsed newlines)
        result = result.replacingOccurrences(
            of: "([a-zA-Z0-9+])#+ ",
            with: "$1 ",
            options: .regularExpression
        )

        // Remove standalone inline headers like "## [Overview]" or "## Overview"
        result = result.replacingOccurrences(
            of: "##+ ",
            with: "",
            options: .regularExpression
        )

        // Split into lines, strip leading header markers, rejoin
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
        let stripped = lines.map { line -> String in
            var strippedLine = String(line)
            // Strip leading # characters and following space
            while strippedLine.hasPrefix("#") {
                strippedLine = String(strippedLine.dropFirst())
            }
            // Remove leading space after # was stripped
            if strippedLine.hasPrefix(" ") {
                strippedLine = String(strippedLine.dropFirst())
            }
            return strippedLine
        }
        result = stripped.joined(separator: "\n")

        // Collapse multiple consecutive newlines to single newline
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result
    }

    /// Splits concatenated HIG titles into readable format
    /// "Tabbars" → "Tab bars", "Navigationandsearch" → "Navigation and search"
    var addingSpacesToCamelCase: String {
        var result = self

        // Common word patterns to split (order matters - longer matches first)
        let patterns: [(find: String, replace: String)] = [
            // Compound patterns
            ("andsearch", " and search"),
            ("andtables", " and tables"),
            // Common suffixes
            ("controls", " controls"),
            ("buttons", " buttons"),
            ("fields", " fields"),
            ("views", " views"),
            ("bars", " bars"),
            // Common prefixes
            ("goingfull", "going full"),
            ("fullscreen", "full screen"),
            ("voiceover", "voice over"),
        ]

        // Apply case-insensitive replacements
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern.find,
                with: pattern.replace,
                options: .caseInsensitive
            )
        }

        // Collapse double spaces that may result from replacements
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Title case the first letter only
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
