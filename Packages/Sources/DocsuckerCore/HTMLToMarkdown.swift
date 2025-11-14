import Foundation
#if canImport(WebKit)
import WebKit
#endif

// MARK: - HTML to Markdown Converter

/// Converts HTML documentation to clean Markdown
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
            return stripHTML(titleHTML)
        }

        if let range = html.range(of: #"<title>(.*?)</title>"#, options: .regularExpression) {
            let titleHTML = String(html[range])
            return stripHTML(titleHTML)
        }

        return nil
    }

    private static func extractMainContent(from html: String) -> String {
        // Try to extract main content area
        // Apple docs typically use <main> or specific class names

        if let mainRange = html.range(of: #"<main[^>]*>(.*?)</main>"#, options: [.regularExpression, .caseInsensitive]) {
            return String(html[mainRange])
        }

        if let articleRange = html.range(of: #"<article[^>]*>(.*?)</article>"#, options: [.regularExpression, .caseInsensitive]) {
            return String(html[articleRange])
        }

        // Fallback to body content
        if let bodyRange = html.range(of: #"<body[^>]*>(.*?)</body>"#, options: [.regularExpression, .caseInsensitive]) {
            return String(html[bodyRange])
        }

        return html
    }

    // MARK: - Conversion

    private static func convertHTMLToMarkdown(_ html: String) -> String {
        var markdown = html

        // Headers
        markdown = markdown.replacingOccurrences(
            of: #"<h1[^>]*>(.*?)</h1>"#,
            with: "# $1\n\n",
            options: .regularExpression
        )
        markdown = markdown.replacingOccurrences(
            of: #"<h2[^>]*>(.*?)</h2>"#,
            with: "## $1\n\n",
            options: .regularExpression
        )
        markdown = markdown.replacingOccurrences(
            of: #"<h3[^>]*>(.*?)</h3>"#,
            with: "### $1\n\n",
            options: .regularExpression
        )
        markdown = markdown.replacingOccurrences(
            of: #"<h4[^>]*>(.*?)</h4>"#,
            with: "#### $1\n\n",
            options: .regularExpression
        )
        markdown = markdown.replacingOccurrences(
            of: #"<h5[^>]*>(.*?)</h5>"#,
            with: "##### $1\n\n",
            options: .regularExpression
        )
        markdown = markdown.replacingOccurrences(
            of: #"<h6[^>]*>(.*?)</h6>"#,
            with: "###### $1\n\n",
            options: .regularExpression
        )

        // Code blocks
        markdown = markdown.replacingOccurrences(
            of: #"<pre[^>]*><code[^>]*>(.*?)</code></pre>"#,
            with: "```\n$1\n```\n\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Inline code
        markdown = markdown.replacingOccurrences(
            of: #"<code[^>]*>(.*?)</code>"#,
            with: "`$1`",
            options: .regularExpression
        )

        // Bold
        markdown = markdown.replacingOccurrences(
            of: #"<(strong|b)[^>]*>(.*?)</\1>"#,
            with: "**$2**",
            options: .regularExpression
        )

        // Italic
        markdown = markdown.replacingOccurrences(
            of: #"<(em|i)[^>]*>(.*?)</\1>"#,
            with: "*$2*",
            options: .regularExpression
        )

        // Links
        markdown = markdown.replacingOccurrences(
            of: #"<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )

        // Lists
        markdown = markdown.replacingOccurrences(
            of: #"<ul[^>]*>(.*?)</ul>"#,
            with: "$1\n",
            options: [.regularExpression, .caseInsensitive]
        )
        markdown = markdown.replacingOccurrences(
            of: #"<ol[^>]*>(.*?)</ol>"#,
            with: "$1\n",
            options: [.regularExpression, .caseInsensitive]
        )
        markdown = markdown.replacingOccurrences(
            of: #"<li[^>]*>(.*?)</li>"#,
            with: "- $1\n",
            options: .regularExpression
        )

        // Paragraphs
        markdown = markdown.replacingOccurrences(
            of: #"<p[^>]*>(.*?)</p>"#,
            with: "$1\n\n",
            options: .regularExpression
        )

        // Line breaks
        markdown = markdown.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)

        // Remove remaining HTML tags
        markdown = stripHTML(markdown)

        // Clean up whitespace
        markdown = markdown.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)

        // Decode HTML entities
        markdown = decodeHTMLEntities(markdown)

        return markdown
    }

    // MARK: - Utilities

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

            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let numberRange = match.range(at: 1)
                    let numberStr = nsString.substring(with: numberRange)

                    if let number = Int(numberStr),
                       let scalar = Unicode.Scalar(number)
                    {
                        let replacement = String(Character(scalar))
                        result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                    }
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
