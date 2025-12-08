import Foundation

// MARK: - Unified Tool Error

/// Unified error type for MCP tool and resource providers.
/// Consolidates error handling across DocumentationToolProvider, SampleCodeToolProvider,
/// CompositeToolProvider, and DocsResourceProvider.
public enum ToolError: Error, LocalizedError, Sendable {
    /// Unknown tool name requested
    case unknownTool(String)

    /// Required argument is missing
    case missingArgument(String)

    /// Invalid argument value with reason
    case invalidArgument(String, String)

    /// Resource not found at URI
    case notFound(String)

    /// Invalid URI format
    case invalidURI(String)

    /// No data available (e.g., no documentation crawled)
    case noData(String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .missingArgument(let arg):
            return "Missing required argument: \(arg)"
        case .invalidArgument(let arg, let reason):
            return "Invalid argument '\(arg)': \(reason)"
        case .notFound(let resource):
            return "Not found: \(resource)"
        case .invalidURI(let uri):
            return "Invalid resource URI: \(uri)"
        case .noData(let message):
            return message
        }
    }
}
