import Foundation

// MARK: - MCP Namespace

/// Namespace for Model Context Protocol (MCP) implementation.
///
/// Layout (in this target only — `MCP.Client`, `MCP.Support`, `MCP.SharedTools`
/// live in sibling SPM targets and extend this same root from their own files):
///
/// - `MCP.Core.Protocols.*`      — wire-format types: requests, responses, content
///                            blocks, capabilities. (Folder on disk is
///                            `Sources/MCP/Core/Protocol/` but the namespace
///                            cannot be named `Protocol` because Swift reserves
///                            `.Protocol` as a metatype member on every type.)
/// - `MCP.Core.Server`      — the server actor implementing the protocol.
///                            Provider protocols + capabilities live as
///                            siblings under `MCP.Core` (Swift's nested-type
///                            rules around protocols inside actors are still
///                            awkward, so they stay at `MCP.Core` level).
/// - `MCP.Core.Transport.*` — transport abstractions: protocol
///                            (`Transport.Channel`), wire envelope
///                            (`Transport.Message`), errors
///                            (`Transport.Failure`), and concrete
///                            implementations (`Transport.Stdio`).
public enum MCP {
    /// Root of the cross-platform MCP runtime (SPM target `MCP`, folder
    /// `Sources/MCP/Core/`). Types live as `MCP.Core.<Category>.<Name>` so
    /// the fully qualified name carries both module and folder of origin.
    public enum Core {
        /// Wire-format types described by the MCP specification: request /
        /// response envelopes, content blocks, server / client capabilities.
        public enum Protocols {}

        /// Transport-layer types. The folder on disk is
        /// `Sources/MCP/Core/Transport/`; the protocol that abstracts a
        /// transport endpoint is `Transport.Channel` (not `Transport`, because
        /// the namespace enum already owns that name).
        public enum Transport {}
    }
}
