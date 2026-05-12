import Foundation

// MARK: - Platform Availability

extension Availability {
    /// Represents platform availability information for an API symbol
    /// Matches Apple's /tutorials/data/documentation API response format
    public struct Platform: Codable, Sendable, Hashable {
        /// Platform name (iOS, macOS, watchOS, etc.)
        public let name: String

        /// Version when this API was introduced (e.g., "13.0", "10.15")
        public let introducedAt: String?

        /// Whether this API is deprecated
        public let deprecated: Bool

        /// Version when this API was deprecated (if applicable)
        public let deprecatedAt: String?

        /// Whether this API is unavailable on this platform
        public let unavailable: Bool

        /// Whether this API is in beta
        public let beta: Bool

        public init(
            name: String,
            introducedAt: String? = nil,
            deprecated: Bool = false,
            deprecatedAt: String? = nil,
            unavailable: Bool = false,
            beta: Bool = false
        ) {
            self.name = name
            self.introducedAt = introducedAt
            self.deprecated = deprecated
            self.deprecatedAt = deprecatedAt
            self.unavailable = unavailable
            self.beta = beta
        }
    }
}

// MARK: - API Response Models

extension Availability {
    /// Response from Apple's /tutorials/data/documentation API
    struct APIResponse: Codable, Sendable {
        let metadata: Metadata?

        struct Metadata: Codable, Sendable {
            let platforms: [PlatformInfo]?
        }

        struct PlatformInfo: Codable, Sendable {
            let name: String
            let introducedAt: String?
            let deprecated: Bool?
            let deprecatedAt: String?
            let unavailable: Bool?
            let beta: Bool?

            func toPlatform() -> Availability.Platform {
                Availability.Platform(
                    name: name,
                    introducedAt: introducedAt,
                    deprecated: deprecated ?? false,
                    deprecatedAt: deprecatedAt,
                    unavailable: unavailable ?? false,
                    beta: beta ?? false
                )
            }
        }
    }
}

// MARK: - Availability Info

extension Availability {
    /// Complete availability information for a documentation page
    public struct Info: Codable, Sendable, Hashable {
        /// Platform availability array
        public let platforms: [Availability.Platform]

        /// When the availability was fetched
        public let fetchedAt: Date

        public init(platforms: [Availability.Platform], fetchedAt: Date = Date()) {
            self.platforms = platforms
            self.fetchedAt = fetchedAt
        }

        /// Empty availability (no data available)
        public static let empty = Availability.Info(platforms: [])

        /// Check if availability data exists
        public var isEmpty: Bool {
            platforms.isEmpty
        }

        /// Minimum iOS version required (nil if not available on iOS)
        public var minimumiOS: String? {
            platforms.first { $0.name == "iOS" && !$0.unavailable }?.introducedAt
        }

        /// Minimum macOS version required (nil if not available on macOS)
        public var minimumMacOS: String? {
            platforms.first { $0.name == "macOS" && !$0.unavailable }?.introducedAt
        }

        /// Check if deprecated on any platform
        public var isDeprecated: Bool {
            platforms.contains { $0.deprecated }
        }

        /// Check if in beta on any platform
        public var isBeta: Bool {
            platforms.contains { $0.beta }
        }
    }
}

// MARK: - @available Annotation Parser

extension Availability.Info {
    /// Parse availability from @available annotations in Swift code
    /// Example: @available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    public static func parseFromAnnotation(_ content: String) -> Availability.Info? {
        // Match @available(iOS 13.0, macOS 10.15, *) pattern
        let pattern = #"@available\s*\(\s*([^)]+)\s*\)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                  in: content,
                  options: [],
                  range: NSRange(content.startIndex..., in: content)
              ),
              let range = Range(match.range(at: 1), in: content)
        else {
            return nil
        }

        let annotationContent = String(content[range])
        var platforms: [Availability.Platform] = []

        // Split by comma and parse each platform
        let parts = annotationContent.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for part in parts {
            // Skip wildcard
            if part == "*" { continue }

            // Parse "iOS 13.0" or "macOS 10.15" or "deprecated" etc.
            let components = part.split(separator: " ", maxSplits: 1)

            if components.count >= 1 {
                let platformName = normalizePlatformName(String(components[0]))
                let version = components.count >= 2 ? String(components[1]) : nil

                // Skip modifiers like "deprecated", "unavailable", "introduced"
                let modifiers = ["deprecated", "unavailable", "introduced", "obsoleted", "message", "renamed"]
                if modifiers.contains(platformName.lowercased()) { continue }

                // Check for deprecated/unavailable modifiers
                let isDeprecated = part.lowercased().contains("deprecated")
                let isUnavailable = part.lowercased().contains("unavailable")

                platforms.append(Availability.Platform(
                    name: platformName,
                    introducedAt: version,
                    deprecated: isDeprecated,
                    deprecatedAt: nil,
                    unavailable: isUnavailable,
                    beta: false
                ))
            }
        }

        return platforms.isEmpty ? nil : Availability.Info(platforms: platforms)
    }

    /// Normalize platform names to match Apple's API format
    private static func normalizePlatformName(_ name: String) -> String {
        switch name.lowercased() {
        case "ios": return "iOS"
        case "ipados": return "iPadOS"
        case "macos", "osx": return "macOS"
        case "tvos": return "tvOS"
        case "watchos": return "watchOS"
        case "visionos": return "visionOS"
        case "maccatalyst", "macCatalyst": return "Mac Catalyst"
        default: return name
        }
    }

    /// Try to extract availability from JSON content (rawMarkdown, codeExamples, declaration)
    public static func extractFromJSONContent(_ jsonData: Data) -> Availability.Info? {
        // Try to parse as dictionary
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // Check rawMarkdown first
        if let rawMarkdown = json["rawMarkdown"] as? String,
           let availability = parseFromAnnotation(rawMarkdown) {
            return availability
        }

        // Check declaration
        if let declaration = json["declaration"] as? [String: Any],
           let code = declaration["code"] as? String,
           let availability = parseFromAnnotation(code) {
            return availability
        }

        // Check code examples
        if let codeExamples = json["codeExamples"] as? [[String: Any]] {
            for example in codeExamples {
                if let code = example["code"] as? String,
                   let availability = parseFromAnnotation(code) {
                    return availability
                }
            }
        }

        return nil
    }
}
