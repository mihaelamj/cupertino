import Foundation
import SharedConstants
import Testing

// MARK: - SharedCore Public API Smoke Tests

// SharedCore is the umbrella residue of the legacy Shared target. Post-
// dissection (refactor 1.6) it owns three concerns only:
// - `Shared.Core` namespace anchor under the top-level `Shared` enum
// - `Shared.Core.ToolError` — the unified error type used by every MCP
//   tool/resource provider and by the `Services.*` actors
// - `CupertinoShared.swift` — `@_exported import Foundation` +
//   `@_exported import CryptoKit` so consumers that `import Shared` (a
//   path that may resurface in dependents) see the symbols transitively.
//
// Per #388 independence acceptance: SharedCore imports only Foundation
// + SharedConstants. No behavioural cross-package import.
// `grep -rln "^import " Packages/Sources/Shared/Core/` returns exactly
// those two imports.
//
// The legacy SharedCoreTests folder also hosts test files that
// historically covered SharedModels / SharedUtils / SharedConfiguration
// before the dissection — those keep running in this target as the
// canonical integration layer. This suite adds focused coverage for
// what actually lives in SharedCore today, so a refactor that drops
// the namespace anchor or breaks ToolError will fail at the leaf.

@Suite("SharedCore public surface")
struct SharedCorePublicSurfaceTests {
    // MARK: Namespace

    @Test("Shared.Core namespace reachable")
    func sharedCoreNamespace() {
        _ = Shared.Core.self
    }

    // MARK: ToolError cases

    @Test("Shared.Core.ToolError.unknownTool has the expected localized description")
    func toolErrorUnknownTool() {
        let error = Shared.Core.ToolError.unknownTool("search_widgets")
        #expect(error.errorDescription == "Unknown tool: search_widgets")
    }

    @Test("Shared.Core.ToolError.missingArgument has the expected localized description")
    func toolErrorMissingArgument() {
        let error = Shared.Core.ToolError.missingArgument("framework")
        #expect(error.errorDescription == "Missing required argument: framework")
    }

    @Test("Shared.Core.ToolError.invalidArgument carries the arg name and reason")
    func toolErrorInvalidArgument() {
        let error = Shared.Core.ToolError.invalidArgument("limit", "must be > 0")
        // The wire format here is shown back to MCP clients (Claude
        // Desktop, Cursor); changing the punctuation would visibly
        // change every error message they render. Pin it.
        #expect(error.errorDescription == "Invalid argument 'limit': must be > 0")
    }

    @Test("Shared.Core.ToolError.notFound has the expected localized description")
    func toolErrorNotFound() {
        let error = Shared.Core.ToolError.notFound("apple-docs://SwiftUI/View")
        #expect(error.errorDescription == "Not found: apple-docs://SwiftUI/View")
    }

    @Test("Shared.Core.ToolError.invalidURI has the expected localized description")
    func toolErrorInvalidURI() {
        let error = Shared.Core.ToolError.invalidURI("garbage://?")
        #expect(error.errorDescription == "Invalid resource URI: garbage://?")
    }

    @Test("Shared.Core.ToolError.noData echoes the supplied message verbatim")
    func toolErrorNoData() {
        // noData is the catch-all for "we have no rows / no crawled
        // pages / no DB"; the message goes straight through. Renaming
        // or auto-prefixing would silently rewrap every consumer's
        // human-written message.
        let message = "No documentation has been crawled yet. Run cupertino fetch first."
        let error = Shared.Core.ToolError.noData(message)
        #expect(error.errorDescription == message)
    }

    // MARK: Error / LocalizedError conformance

    @Test("Shared.Core.ToolError conforms to Error and LocalizedError")
    func toolErrorConformances() {
        // Compile-time check via existential casts. If a refactor
        // ever drops LocalizedError, the MCP tool-error path stops
        // rendering descriptions in error responses.
        let error = Shared.Core.ToolError.unknownTool("x")
        let asError: Error = error
        let asLocalized: LocalizedError? = error
        _ = asError
        #expect(asLocalized?.errorDescription != nil)
    }
}
