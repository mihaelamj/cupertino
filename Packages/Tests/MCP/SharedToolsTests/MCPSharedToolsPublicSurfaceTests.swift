import Foundation
import MCPCore
@testable import MCPSharedTools
import Testing

// MARK: - MCPSharedTools Public API Smoke Tests

// MCPSharedTools sits over MCPCore + SharedConstants + SharedCore. It
// owns:
// - MCP.SharedTools namespace anchor
// - MCP.SharedTools.ArgumentExtractor — the MCP tool-input parser used
//   by every MCP tool provider (covered by ArgumentExtractorTests in
//   this same target)
// - MCP.SharedTools.Copy — the human-readable strings shipped to MCP
//   clients (Claude Desktop, Cursor): tool descriptions, resource
//   template URIs, descriptions, MIME types
//
// Per #390 independence acceptance: MCPSharedTools imports only
// Foundation + MCPCore + SharedConstants + SharedCore. No behavioural
// cross-package import.
// `grep -rln "^import " Packages/Sources/MCP/SharedTools/` returns
// exactly those four imports.
//
// ArgumentExtractor coverage already exists at
// ArgumentExtractorTests.swift (18 tests). This suite adds:
// - the namespace anchor itself
// - the Copy constants: URI templates, MIME types, and a representative
//   slice of the tool/resource description strings that MCP clients
//   surface verbatim
//
// Pinning the URI templates is critical because MCP clients template-
// substitute against them, and pinning the description strings catches
// the class of refactor that accidentally rewrites copy that's been
// stable on the wire.

@Suite("MCPSharedTools public surface")
struct MCPSharedToolsPublicSurfaceTests {
    // MARK: Namespace

    @Test("MCP.SharedTools namespace reachable")
    func mcpSharedToolsNamespace() {
        _ = MCP.SharedTools.self
        _ = MCP.SharedTools.Copy.self
    }

    // MARK: Resource template URIs

    @Test("Resource template URIs match the MCP wire contract")
    func resourceTemplateURIs() {
        // The MCP client substitutes {framework}/{page} and {proposalID}
        // against these literals. Renaming a placeholder breaks every
        // resource subscription on the client side; pin the exact form.
        #expect(MCP.SharedTools.Copy.templateAppleDocs == "apple-docs://{framework}/{page}")
        #expect(MCP.SharedTools.Copy.templateSwiftEvolution == "swift-evolution://{proposalID}")
    }

    // MARK: Resource description strings

    @Test("Apple docs / Swift Evolution resource description strings match the wire format")
    func resourceDescriptions() {
        #expect(MCP.SharedTools.Copy.appleDocsDescriptionPrefix == "Apple Documentation:")
        #expect(MCP.SharedTools.Copy.swiftEvolutionDescription == "Swift Evolution Proposal")
        #expect(MCP.SharedTools.Copy.appleDocsTemplateName == "Apple Documentation Page")
        #expect(MCP.SharedTools.Copy.appleDocsTemplateDescription == "Access Apple documentation by framework and page name")
        #expect(MCP.SharedTools.Copy.swiftEvolutionTemplateDescription.contains("Swift Evolution proposals"))
        #expect(MCP.SharedTools.Copy.swiftEvolutionTemplateDescription.contains("SE-0001"))
        #expect(MCP.SharedTools.Copy.swiftEvolutionTemplateDescription.contains("ST-0001"))
    }

    // MARK: MIME type

    @Test("Markdown MIME type pinned to text/markdown")
    func markdownMIMEType() {
        // Used in every Apple-docs resources/read response. Renaming
        // would silently regress client-side rendering paths that key
        // off mimeType.
        #expect(MCP.SharedTools.Copy.mimeTypeMarkdown == "text/markdown")
    }

    // MARK: Tool descriptions — invariant slices

    @Test("Unified search tool description carries every source option keyword")
    func searchToolDescriptionMentionsAllSources() {
        let desc = MCP.SharedTools.Copy.toolSearchDescription
        // The description guides LLM tool routing; missing a source
        // option here means the model won't know it can pass that
        // value. Pin the source-list footprint.
        for source in [
            "apple-docs",
            "samples",
            "hig",
            "apple-archive",
            "swift-evolution",
            "swift-org",
            "swift-book",
            "packages",
        ] {
            #expect(desc.contains(source), "search description missing source: \(source)")
        }
    }

    @Test("Unified search description mentions the limit / availability / framework filters")
    func searchToolDescriptionMentionsFilterParameters() {
        let desc = MCP.SharedTools.Copy.toolSearchDescription
        #expect(desc.contains("limit"))
        #expect(desc.contains("framework"))
        #expect(desc.contains("min_ios"))
        #expect(desc.contains("min_macos"))
        #expect(desc.contains("min_tvos"))
        #expect(desc.contains("min_watchos"))
        #expect(desc.contains("min_visionos"))
        #expect(desc.contains("include_archive"))
        #expect(desc.contains("source"))
    }

    @Test("Documentation tool descriptions are non-empty")
    func documentationToolDescriptionsNonEmpty() {
        // Sanity floor: no string is ever empty. Catches an accidental
        // = "" assignment that would silently strip the description
        // from any MCP client tool list.
        #expect(!MCP.SharedTools.Copy.toolListFrameworksDescription.isEmpty)
        #expect(!MCP.SharedTools.Copy.toolReadDocumentDescription.isEmpty)
        #expect(!MCP.SharedTools.Copy.toolListSamplesDescription.isEmpty)
        #expect(!MCP.SharedTools.Copy.toolReadSampleDescription.isEmpty)
        #expect(!MCP.SharedTools.Copy.toolReadSampleFileDescription.isEmpty)
    }

    @Test("Semantic search tool descriptions mention their key parameters")
    func semanticSearchDescriptionsPinParameters() {
        // Tool descriptions are the LLM's only signal about parameter
        // names; pin the key parameter names per tool so a refactor
        // doesn't silently break tool calls.
        #expect(MCP.SharedTools.Copy.toolSearchSymbolsDescription.contains("kind"))
        #expect(MCP.SharedTools.Copy.toolSearchSymbolsDescription.contains("is_async"))
        #expect(MCP.SharedTools.Copy.toolSearchPropertyWrappersDescription.contains("wrapper"))
        #expect(MCP.SharedTools.Copy.toolSearchConcurrencyDescription.contains("pattern"))
        #expect(MCP.SharedTools.Copy.toolSearchConformancesDescription.contains("protocol"))
    }
}
