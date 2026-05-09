import Foundation
import Shared
import SQLite3

// swiftlint:disable function_body_length
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

extension Search.Index {
    func detectLanguage(from content: String) -> String {
        // Look for Objective-C indicators
        let objcPatterns = [
            "#import",
            "@interface",
            "@implementation",
            "@property",
            "@synthesize",
            "@selector",
            "NSObject",
            "- (void)",
            "- (id)",
            "+ (void)",
            "+ (id)",
            "[[",
            "]]",
        ]

        let lowercased = content.lowercased()

        // Check for Obj-C patterns
        for pattern in objcPatterns {
            if content.contains(pattern) || lowercased.contains(pattern.lowercased()) {
                return "objc"
            }
        }

        // Default to Swift (most Apple docs are Swift)
        return "swift"
    }

    // MARK: - Availability Extraction

    /// Extracted availability data from JSON.
    /// Internal (not private) so it can be the return type of the internal
    /// `extractAvailabilityFromJSON` consumed from sibling extension files.
    struct ExtractedAvailability {
        var iOS: String?
        var macOS: String?
        var tvOS: String?
        var watchOS: String?
        var visionOS: String?
        var source: String? // 'api', 'parsed', 'inherited', 'derived'
    }

    /// Extract availability from JSON string
    func extractAvailabilityFromJSON(_ jsonString: String) -> ExtractedAvailability {
        var result = ExtractedAvailability()

        let data = Data(jsonString.utf8)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let availabilityArray = json["availability"] as? [[String: Any]]
        else {
            return result
        }

        // If availability array is empty, no availability data
        guard !availabilityArray.isEmpty else {
            return result
        }

        // Determine source based on presence of availability
        result.source = "api" // Default - could be enhanced to detect 'inherited', 'derived'

        for platform in availabilityArray {
            guard let name = platform["name"] as? String,
                  let introducedAt = platform["introducedAt"] as? String,
                  platform["unavailable"] as? Bool != true
            else { continue }

            switch name.lowercased() {
            case "ios", "ipados":
                if result.iOS == nil || isVersionGreater(introducedAt, than: result.iOS!) {
                    result.iOS = introducedAt
                }
            case "macos":
                result.macOS = introducedAt
            case "tvos":
                result.tvOS = introducedAt
            case "watchos":
                result.watchOS = introducedAt
            case "visionos":
                result.visionOS = introducedAt
            default:
                break
            }
        }

        return result
    }

    /// Compare version strings - returns true if lhs > rhs
    func isVersionGreater(_ lhs: String, than rhs: String) -> Bool {
        let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
        let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }

        for idx in 0..<max(lhsComponents.count, rhsComponents.count) {
            let lhsValue = idx < lhsComponents.count ? lhsComponents[idx] : 0
            let rhsValue = idx < rhsComponents.count ? rhsComponents[idx] : 0

            if lhsValue > rhsValue { return true }
            if lhsValue < rhsValue { return false }
        }
        return false
    }

    /// Helper to bind optional text to SQLite statement
    func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func extractSummary(
        from content: String,
        maxLength: Int = Shared.Constants.ContentLimit.summaryMaxLength
    ) -> String {
        // Remove YAML front matter
        var cleaned = content

        // Find and remove front matter (--- ... ---)
        if let firstDash = content.range(of: "---")?.lowerBound {
            if let secondDash = content.range(
                of: "---",
                range: content.index(after: firstDash)..<content.endIndex
            )?.upperBound {
                cleaned = String(content[secondDash...])
            }
        }

        // Remove markdown headers at the start
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix("#") {
            if let newlineIndex = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: newlineIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }

        // Remove repeated title lines at the start (used for BM25 boosting)
        // Filter empty lines first to handle "Title\n\nTitle\n\nTitle" pattern
        var lines = cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Remove consecutive duplicate lines at the start
        while lines.count > 1, lines[0] == lines[1] {
            lines.removeFirst()
        }

        cleaned = lines.joined(separator: "\n\n")

        // Take first maxLength chars
        let truncated = String(cleaned.prefix(maxLength))

        // Find last sentence boundary
        if let lastPeriod = truncated.lastIndex(of: "."),
           truncated.distance(from: truncated.startIndex, to: lastPeriod) > 100 {
            return String(truncated[...lastPeriod])
        }

        // Otherwise, find last space to avoid cutting words
        if truncated.count == maxLength,
           let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }

        return truncated
    }
}
