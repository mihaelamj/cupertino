import Foundation
import MCP

// MARK: - MCP.SharedTools Namespace

/// Sub-namespace under the MCP root for utilities shared between every MCP
/// SPM target in the monorepo (MCP, MCP.Support, MCP.Client, plus the CLI's
/// `SearchToolProvider` consumer). Holds `MCP.SharedTools.ArgumentExtractor`
/// for type-safe MCP tool-argument extraction and `MCP.SharedTools.Copy`
/// for MCP-protocol output strings (resource template URIs, MIME types,
/// tool descriptions) that are emitted back to clients.
extension MCP {
    public enum SharedTools {}
}
