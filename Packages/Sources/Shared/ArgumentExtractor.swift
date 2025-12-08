import Foundation
import MCP

// MARK: - Argument Extractor

/// Helper for extracting and validating MCP tool arguments.
/// Reduces boilerplate in tool providers by providing type-safe access to arguments.
public struct ArgumentExtractor: Sendable {
    private let arguments: [String: AnyCodable]?

    /// Initialize with MCP tool arguments
    public init(_ arguments: [String: AnyCodable]?) {
        self.arguments = arguments
    }

    // MARK: - Required Arguments

    /// Extract a required string argument, throwing if missing
    public func require(_ key: String) throws -> String {
        guard let value = arguments?[key]?.value as? String else {
            throw ToolError.missingArgument(key)
        }
        return value
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
    public func optional(_ key: String) -> String? {
        arguments?[key]?.value as? String
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
    public func optional(_ key: String, default defaultValue: String) -> String {
        (arguments?[key]?.value as? String) ?? defaultValue
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
        key: String = Shared.Constants.MCP.schemaParamLimit,
        default defaultLimit: Int = Shared.Constants.Limit.defaultSearchLimit
    ) -> Int {
        let requested = optional(key, default: defaultLimit)
        return min(requested, Shared.Constants.Limit.maxSearchLimit)
    }

    /// Extract a format argument for document output
    public func format(
        key: String = Shared.Constants.MCP.schemaParamFormat,
        default defaultFormat: String = Shared.Constants.MCP.formatValueJSON
    ) -> String {
        optional(key, default: defaultFormat)
    }

    /// Check if include_archive flag is set
    public func includeArchive(
        key: String = Shared.Constants.MCP.schemaParamIncludeArchive
    ) -> Bool {
        optional(key, default: false)
    }
}
