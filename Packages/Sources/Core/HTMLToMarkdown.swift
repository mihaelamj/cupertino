import Foundation
import Shared
#if canImport(WebKit)
import WebKit
#endif

// MARK: - HTML to Markdown Converter

// swiftlint:disable type_body_length
// Justification: This file contains a comprehensive HTML-to-Markdown converter
// with specialized handling for documentation pages. The conversion logic includes:
// - Content extraction from various HTML structures (main, article, body)
// - Code block protection and restoration to prevent mangling
// - HTML element conversion (headers, links, lists, formatting)
// - Entity decoding and cleanup
// - Removal of unwanted UI elements (JavaScript warnings, accessibility instructions)
// Splitting this into multiple files would break the logical cohesion of the conversion
// pipeline and make it harder to understand the sequential transformation steps.
// The file is well-organized with clear MARK comments separating concerns.
// File length: 580+ lines | Type body length: 400+ lines
// Disabling: file_length (400 line limit), type_body_length (250 line limit)

// Converts HTML documentation to clean Markdown
public enum HTMLToMarkdown {
    /// Convert HTML string to Markdown
    public static func convert(_ html: String, url: URL) -> String {
        var markdown = ""

        // Add front matter with metadata
        markdown += "---\n"
        markdown += "source: \(url.absoluteString)\n"
        markdown += "crawled: \(ISO8601DateFormatter().string(from: Date()))\n"
        markdown += "---\n\n"

        // Extract title
        if let title = extractTitle(from: html) {
            markdown += "# \(title)\n\n"
        }

        // Extract main content
        let content = extractMainContent(from: html)
        markdown += convertHTMLToMarkdown(content)

        return markdown
    }

    // MARK: - Extraction

    private static func extractTitle(from html: String) -> String? {
        // Try to extract title from <h1> or <title> tags
        if let range = html.range(of: #"<h1[^>]*>(.*?)</h1>"#, options: .regularExpression) {
            let titleHTML = String(html[range])
            let title = stripHTML(titleHTML)
            // Skip if it's a JavaScript warning
            if !isJavaScriptWarning(title) {
                return title
            }
        }

        if let range = html.range(of: #"<title>(.*?)</title>"#, options: .regularExpression) {
            let titleHTML = String(html[range])
            let title = stripHTML(titleHTML)
            // Skip if it's a JavaScript warning
            if !isJavaScriptWarning(title) {
                return title
            }
        }

        return nil
    }

    private static func isJavaScriptWarning(_ text: String) -> Bool {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lowercased.contains("requires javascript") ||
            lowercased.contains("enable javascript") ||
            lowercased.contains("javascript is required")
    }

    private static func extractMainContent(from html: String) -> String {
        // Try to extract main content area - need dotMatchesLineSeparators for multiline content
        let options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

        if let regex = try? NSRegularExpression(pattern: #"<main[^>]*>(.*?)</main>"#, options: options),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range, in: html) {
            return String(html[range])
        }

        if let regex = try? NSRegularExpression(pattern: #"<article[^>]*>(.*?)</article>"#, options: options),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range, in: html) {
            return String(html[range])
        }

        // Fallback to body content
        if let regex = try? NSRegularExpression(pattern: #"<body[^>]*>(.*?)</body>"#, options: options),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range, in: html) {
            return String(html[range])
        }

        return html
    }

    // MARK: - Conversion

    private static func convertHTMLToMarkdown(_ html: String) -> String {
        var markdown = html

        // Step 1: Remove unwanted sections BEFORE extracting content
        markdown = removeUnwantedSections(markdown)

        // Step 2: Extract and protect code blocks to prevent them from being mangled
        var codeBlocks: [String: String] = [:]
        markdown = extractAndProtectCodeBlocks(markdown, into: &codeBlocks)

        // Step 3: Remove UI clutter
        markdown = removeJavaScriptWarnings(markdown)
        markdown = removeAccessibilityInstructions(markdown)

        // Step 4: Convert HTML elements to markdown
        markdown = convertHeaders(markdown)
        markdown = convertInlineFormatting(markdown)
        markdown = convertLinks(markdown)
        markdown = convertLists(markdown)
        markdown = convertParagraphs(markdown)

        // Step 5: Final cleanup
        markdown = stripHTML(markdown)
        markdown = cleanupWhitespace(markdown)
        markdown = decodeHTMLEntities(markdown)

        // Step 6: Restore protected code blocks
        markdown = restoreCodeBlocks(markdown, from: codeBlocks)

        return markdown
    }

    private static func extractAndProtectCodeBlocks(
        _ html: String,
        into storage: inout [String: String]
    ) -> String {
        var result = html
        var blockIndex = 0
        let regexOptions: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

        // Extract <pre><code> blocks with language
        let pattern = CupertinoConstants.Pattern.htmlCodeBlockWithLanguage
        if let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() where match.numberOfRanges >= 3 {
                let languageRange = match.range(at: 1)
                let codeRange = match.range(at: 2)

                if languageRange.location != NSNotFound, codeRange.location != NSNotFound {
                    let language = nsString.substring(with: languageRange).lowercased()
                    var code = nsString.substring(with: codeRange)

                    // Strip HTML tags and decode entities from code
                    code = stripHTML(code)
                    code = decodeHTMLEntities(code)

                    let placeholder = "___CODEBLOCK_\(blockIndex)___"
                    storage[placeholder] = "```\(language)\n\(code)\n```"
                    result = (result as NSString).replacingCharacters(in: match.range, with: placeholder)
                    blockIndex += 1
                }
            }
        }

        // Fallback: Extract <pre><code> blocks without language
        let fallbackPattern = #"<pre[^>]*>\s*<code[^>]*>(.*?)</code>\s*</pre>"#
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: regexOptions) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() where match.numberOfRanges >= 2 {
                let codeRange = match.range(at: 1)
                if codeRange.location != NSNotFound {
                    var code = nsString.substring(with: codeRange)

                    // Strip HTML tags and decode entities from code
                    code = stripHTML(code)
                    code = decodeHTMLEntities(code)

                    let placeholder = "___CODEBLOCK_\(blockIndex)___"
                    storage[placeholder] = "```\n\(code)\n```"
                    result = (result as NSString).replacingCharacters(in: match.range, with: placeholder)
                    blockIndex += 1
                }
            }
        }

        return result
    }

    private static func restoreCodeBlocks(_ markdown: String, from storage: [String: String]) -> String {
        var result = markdown
        for (placeholder, code) in storage {
            result = result.replacingOccurrences(of: placeholder, with: "\n\n\(code)\n\n")
        }
        return result
    }

    private static func convertHeaders(_ markdown: String) -> String {
        var result = markdown
        result = result.replacingOccurrences(
            of: #"<h1[^>]*>(.*?)</h1>"#, with: "# $1\n\n", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<h2[^>]*>(.*?)</h2>"#, with: "## $1\n\n", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<h3[^>]*>(.*?)</h3>"#, with: "### $1\n\n", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<h4[^>]*>(.*?)</h4>"#, with: "#### $1\n\n", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<h5[^>]*>(.*?)</h5>"#, with: "##### $1\n\n", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"<h6[^>]*>(.*?)</h6>"#, with: "###### $1\n\n", options: .regularExpression
        )
        return result
    }

    private static func convertInlineFormatting(_ markdown: String) -> String {
        var result = markdown
        let regexOptions: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

        // Inline code (use dotMatchesLineSeparators to handle multiline code)
        if let regex = try? NSRegularExpression(pattern: #"<code[^>]*>(.*?)</code>"#, options: regexOptions) {
            let nsString = result as NSString
            let range = NSRange(location: 0, length: nsString.length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "`$1`")
        }

        // Bold
        if let regex = try? NSRegularExpression(pattern: #"<(strong|b)[^>]*>(.*?)</\1>"#, options: regexOptions) {
            let nsString = result as NSString
            let range = NSRange(location: 0, length: nsString.length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "**$2**")
        }

        // Italic
        if let regex = try? NSRegularExpression(pattern: #"<(em|i)[^>]*>(.*?)</\1>"#, options: regexOptions) {
            let nsString = result as NSString
            let range = NSRange(location: 0, length: nsString.length)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "*$2*")
        }

        return result
    }

    private static func convertLinks(_ markdown: String) -> String {
        markdown.replacingOccurrences(
            of: #"<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )
    }

    private static func convertLists(_ markdown: String) -> String {
        var result = markdown

        // Convert list items first (need dotMatchesLineSeparators for multiline items)
        if let regex = try? NSRegularExpression(
            pattern: #"<li[^>]*>(.*?)</li>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let nsString = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: "\n- $1\n"
            )
        }

        // Then remove list containers
        if let regex = try? NSRegularExpression(
            pattern: #"<ul[^>]*>(.*?)</ul>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let nsString = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: "$1\n\n"
            )
        }

        if let regex = try? NSRegularExpression(
            pattern: #"<ol[^>]*>(.*?)</ol>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let nsString = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: "$1\n\n"
            )
        }

        return result
    }

    private static func convertParagraphs(_ markdown: String) -> String {
        var result = markdown
        result = result.replacingOccurrences(of: #"<p[^>]*>(.*?)</p>"#, with: "$1\n\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        return result
    }

    private static func cleanupWhitespace(_ markdown: String) -> String {
        var result = markdown
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // MARK: - Utilities

    private static func removeUnwantedSections(_ html: String) -> String {
        var result = html

        // Remove noscript tags and their content
        result = result.replacingOccurrences(
            of: #"<noscript[^>]*>.*?</noscript>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove script tags
        result = result.replacingOccurrences(
            of: #"<script[^>]*>.*?</script>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove style tags
        result = result.replacingOccurrences(
            of: #"<style[^>]*>.*?</style>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove navigation elements
        result = result.replacingOccurrences(
            of: #"<nav[^>]*>.*?</nav>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove header/footer elements (often contain navigation)
        result = result.replacingOccurrences(
            of: #"<header[^>]*>.*?</header>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"<footer[^>]*>.*?</footer>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove SVG elements (icons, graphics) - use dotMatchesLineSeparators for multiline SVG
        if let regex = try? NSRegularExpression(
            pattern: #"<svg[^>]*>.*?</svg>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let nsString = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
        }

        return result
    }

    private static func removeJavaScriptWarnings(_ html: String) -> String {
        var result = html

        // Common JavaScript warning patterns - remove from anywhere in text
        let warnings = [
            "This page requires JavaScript.",
            "This page requires JavaScript",
            "Please turn on JavaScript",
            "Please enable JavaScript",
            "JavaScript is required",
            "Enable JavaScript to view",
        ]

        for warning in warnings {
            result = result.replacingOccurrences(of: warning, with: "", options: .caseInsensitive)
        }

        // Remove common heading patterns for JavaScript warnings (with any number of #)
        result = result.replacingOccurrences(
            of: #"#{1,6}\s*This page requires JavaScript\.?\s*\n+"#,
            with: "",
            options: .regularExpression
        )

        // Also remove if it appears as plain text at start of line
        if let regex = try? NSRegularExpression(
            pattern: #"^\s*This page requires JavaScript\.?\s*\n+"#,
            options: [.anchorsMatchLines]
        ) {
            let nsString = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
        }

        return result
    }

    private static func removeAccessibilityInstructions(_ markdown: String) -> String {
        var result = markdown
        result = removeNavigationInstructions(result)
        result = removeSymbolIndicators(result)
        result = removeSkipNavigation(result)
        result = removeArtifacts(result)
        result = cleanupStrayCharacters(result)
        return result
    }

    private static func removeNavigationInstructions(_ markdown: String) -> String {
        var result = markdown
        result = result.replacingOccurrences(
            of: #"To navigate the symbols, press Up Arrow, Down Arrow, Left Arrow or Right Arrow\s*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\d+ items were found\. Tab back to navigate through them\.\s*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"/\s*Navigator is ready -\s*"#,
            with: "",
            options: .regularExpression
        )
        return result
    }

    private static func removeSymbolIndicators(_ markdown: String) -> String {
        var result = markdown
        result = result.replacingOccurrences(
            of: #"\s*[A-Za-z0-9#]*\d+ of \d+ symbols inside [^\n\[\]]+\s*"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"containing \d+ symbols"#,
            with: "",
            options: .regularExpression
        )
        return result
    }

    private static func removeSkipNavigation(_ markdown: String) -> String {
        var result = markdown
        result = result.replacingOccurrences(
            of: #"\[\s*Skip Navigation\s*\]\s*\(#[^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\[\s*Skip Navigation\s*\]"#,
            with: "",
            options: .regularExpression
        )
        return result
    }

    private static func removeArtifacts(_ markdown: String) -> String {
        var result = markdown
        result = result.replacingOccurrences(of: #"\[object Object\]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*data-v-[a-z0-9]+="[^"]*""#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"  +"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n\n\n+"#, with: "\n\n", options: .regularExpression)
        return result
    }

    private static func cleanupStrayCharacters(_ markdown: String) -> String {
        var result = markdown
        if let regex = try? NSRegularExpression(
            pattern: #"^\s*">+\s*"#,
            options: [.anchorsMatchLines]
        ) {
            let nsString = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
        }
        result = result.replacingOccurrences(
            of: #"\n\s*">+\s*\n"#,
            with: "\n",
            options: .regularExpression
        )
        return result
    }

    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        // Common HTML entities
        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#39;": "'",
            "&#x27;": "'",
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Numeric entities (&#123;) - simple regex replacement
        if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() where match.numberOfRanges >= 2 {
                let numberRange = match.range(at: 1)
                let numberStr = nsString.substring(with: numberRange)

                if let number = Int(numberStr),
                   let scalar = Unicode.Scalar(number) {
                    let replacement = String(Character(scalar))
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        return result
    }
}

// MARK: - String Extension for Regex Replacements

extension String {
    func replacingOccurrences(
        of pattern: String,
        with template: String,
        options: NSRegularExpression.Options = [],
        using closure: ((Substring) -> String)? = nil
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return self
        }

        let range = NSRange(startIndex..., in: self)
        var result = self

        let matches = regex.matches(in: self, range: range).reversed()

        for match in matches {
            if let closure {
                if let matchRange = Range(match.range, in: self) {
                    let replacement = closure(self[matchRange])
                    result.replaceSubrange(matchRange, with: replacement)
                }
            } else {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: match.range,
                    withTemplate: template
                )
            }
        }

        return result
    }
}
