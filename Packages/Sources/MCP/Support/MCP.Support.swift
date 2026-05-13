import Foundation
import MCPCore

// MARK: - MCP.Support Namespace

/// Sub-namespace under the MCP root for support utilities — server-side
/// helpers that aren't part of the cross-platform protocol runtime but ship
/// alongside it in the same SPM target family.
///
/// Holds `MCP.Support.DocsResourceProvider`, the resource provider that
/// serves crawled Apple documentation through the MCP resource interface.
extension MCP {
    public enum Support {}
}
