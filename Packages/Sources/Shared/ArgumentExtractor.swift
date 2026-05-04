import Foundation
import MCP

// MARK: - Argument Extractor

/// Helper for extracting and validating MCP tool arguments.
/// Reduces boilerplate in tool providers by providing type-safe access to arguments.
public struct ArgumentExtractor: Sendable {
    // why: search queries / URIs should never exceed this; defense against malformed
    // or hostile input from the host LLM (indirect prompt injection / payload DoS).
    public static let maxStringLength = 16 * 1024

    private let arguments: [String: AnyCodable]?

    /// Initialize with MCP tool arguments
    public init(_ arguments: [String: AnyCodable]?) {
        self.arguments = arguments
    }

    // MARK: - Validation

    private static func validate(_ key: String, _ value: String) throws -> String {
        // utf8.count is more conservative than .count because a single Character
        // can be many bytes; we cap on the wire size, not the grapheme count.
        if value.utf8.count > maxStringLength {
            throw ToolError.invalidArgument(
                key,
                "value exceeds maximum length of \(maxStringLength) bytes"
            )
        }
        return value
    }

    // MARK: - Required Arguments

    /// Extract a required string argument, throwing if missing
    public func require(_ key: String) throws -> String {
        guard let value = arguments?[key]?.value as? String else {
            throw ToolError.missingArgument(key)
        }
        return try Self.validate(key, value)
    }

    /// Extract a required integer argument, throwing if missing
    public func requireInt(_ key: String) throws -> Int {
        guard let value = arguments?[key]?.value as? Int else {
            throw ToolError.missingArgument(key)
        }
        return value
    }

    /// Extract a required boolean argument, throwing if missing
    public func requireBool(_ key: String) throws -> Bool {
        guard let value = arguments?[key]?.value as? Bool else {
            throw ToolError.missingArgument(key)
        }
        return value
    }

    // MARK: - Optional Arguments

    /// Extract an optional string argument
    public func optional(_ key: String) throws -> String? {
        guard let value = arguments?[key]?.value as? String else {
            return nil
        }
        return try Self.validate(key, value)
    }

    /// Extract an optional integer argument
    public func optionalInt(_ key: String) -> Int? {
        arguments?[key]?.value as? Int
    }

    /// Extract an optional boolean argument
    public func optionalBool(_ key: String) -> Bool? {
        arguments?[key]?.value as? Bool
    }

    // MARK: - Arguments with Defaults

    /// Extract a string argument with a default value
    public func optional(_ key: String, default defaultValue: String) throws -> String {
        guard let value = arguments?[key]?.value as? String else {
            return defaultValue
        }
        return try Self.validate(key, value)
    }

    /// Extract an integer argument with a default value
    public func optional(_ key: String, default defaultValue: Int) -> Int {
        (arguments?[key]?.value as? Int) ?? defaultValue
    }

    /// Extract a boolean argument with a default value
    public func optional(_ key: String, default defaultValue: Bool) -> Bool {
        (arguments?[key]?.value as? Bool) ?? defaultValue
    }

    // MARK: - Specialized Extractors

    /// Extract a limit argument, clamped to the max search limit
    public func limit(
        key: String = Shared.Constants.Search.schemaParamLimit,
        default defaultLimit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) -> Int {
        let requested = optional(key, default: defaultLimit)
        return min(requested, Shared.Constants.Limit.maxSearchLimit)
    }

    /// Extract a format argument for document output
    public func format(
        key: String = Shared.Constants.Search.schemaParamFormat,
        default defaultFormat: String = Shared.Constants.Search.formatValueJSON
    ) throws -> String {
        try optional(key, default: defaultFormat)
    }

    /// Check if include_archive flag is set
    public func includeArchive(
        key: String = Shared.Constants.Search.schemaParamIncludeArchive
    ) -> Bool {
        optional(key, default: false)
    }

    /// Extract min_ios version filter
    public func minIOS(
        key: String = Shared.Constants.Search.schemaParamMinIOS
    ) throws -> String? {
        try optional(key)
    }

    /// Extract min_macos version filter
    public func minMacOS(
        key: String = Shared.Constants.Search.schemaParamMinMacOS
    ) throws -> String? {
        try optional(key)
    }

    /// Extract min_tvos version filter
    public func minTvOS(
        key: String = Shared.Constants.Search.schemaParamMinTvOS
    ) throws -> String? {
        try optional(key)
    }

    /// Extract min_watchos version filter
    public func minWatchOS(
        key: String = Shared.Constants.Search.schemaParamMinWatchOS
    ) throws -> String? {
        try optional(key)
    }

    /// Extract min_visionos version filter
    public func minVisionOS(
        key: String = Shared.Constants.Search.schemaParamMinVisionOS
    ) throws -> String? {
        try optional(key)
    }
}
