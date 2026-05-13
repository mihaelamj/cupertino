import Foundation
import SharedConstants

// MARK: - Shared.Core Namespace

extension Shared {
    /// Cross-cutting core utility types shared across the codebase.
    /// Currently hosts `Shared.Core.ToolError` — the unified error type used by
    /// every MCP tool/resource provider and by the `Services.*` actors.
    /// Mirrors the `Sources/Shared/Core/` folder on disk.
    public enum Core {}
}
