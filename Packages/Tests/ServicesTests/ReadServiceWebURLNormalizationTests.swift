import Foundation
@testable import Services
import ServicesModels
import SharedConstants
import Testing

// MARK: - #587 — Services.ReadService web-URL normalisation
//
// Pin the input-side normalisation that lets `cupertino read` (and the
// MCP `read_document` tool, which mirrors the same logic) accept
// canonical Apple Developer URLs. Pre-#587 a paste-and-run flow with
// `https://developer.apple.com/documentation/swiftui/view` produced
// `Document not found in search.db` and exit 1 — the entry point
// required the `apple-docs://` URI form. These tests pin the new
// pass-through semantics: web URL gets rewritten, every other shape
// flows through untouched.

@Suite("Services.ReadService.normalizeIdentifier (#587 web URL → URI)")
struct ReadServiceNormalizeIdentifierTests {
    typealias SUT = Services.ReadService

    @Test("Canonical Apple Developer web URL → lossless apple-docs URI")
    func appleDeveloperWebURLConvertsToURI() {
        let raw = "https://developer.apple.com/documentation/swiftui/view"
        #expect(SUT.normalizeIdentifier(raw) == "apple-docs://swiftui/view")
    }

    @Test("Deeply nested Apple URL: every path segment preserved verbatim")
    func deepURLConvertsLosslessly() {
        let raw = "https://developer.apple.com/documentation/swiftui/toolbarrole/navigationstack"
        #expect(SUT.normalizeIdentifier(raw) == "apple-docs://swiftui/toolbarrole/navigationstack")
    }

    @Test("Mixed-case web URL is normalised per #283 canonicalisation")
    func mixedCaseURLLowercases() {
        let raw = "https://developer.apple.com/documentation/SwiftUI/View"
        #expect(SUT.normalizeIdentifier(raw) == "apple-docs://swiftui/view")
    }

    @Test("Web URL with query and fragment strips both")
    func webURLStripsQueryAndFragment() {
        let raw = "https://developer.apple.com/documentation/swiftui/view?language=swift#discussion"
        #expect(SUT.normalizeIdentifier(raw) == "apple-docs://swiftui/view")
    }

    @Test("Framework-root Apple URL → framework-only URI")
    func frameworkRootURL() {
        let raw = "https://developer.apple.com/documentation/swiftui"
        #expect(SUT.normalizeIdentifier(raw) == "apple-docs://swiftui")
    }

    @Test("Existing apple-docs URI passes through unchanged")
    func appleDocsURIPassesThrough() {
        let raw = "apple-docs://swiftui/view"
        #expect(SUT.normalizeIdentifier(raw) == raw)
    }

    @Test("Swift Evolution URI passes through unchanged")
    func evolutionURIPassesThrough() {
        let raw = "swift-evolution://SE-0255"
        #expect(SUT.normalizeIdentifier(raw) == raw)
    }

    @Test("Package identifier (owner/repo/path) passes through unchanged")
    func packageIdentifierPassesThrough() {
        let raw = "apple/swift-collections/Sources/OrderedCollections/OrderedSet.swift"
        #expect(SUT.normalizeIdentifier(raw) == raw)
    }

    @Test("Sample identifier passes through unchanged")
    func sampleIdentifierPassesThrough() {
        let raw = "swiftui-landmarks-sample"
        #expect(SUT.normalizeIdentifier(raw) == raw)
    }

    @Test("Non-Apple web URL passes through unchanged (existing dispatch rejects it later)")
    func nonAppleWebURLPassesThrough() {
        let raw = "https://github.com/apple/swift"
        #expect(SUT.normalizeIdentifier(raw) == raw)
    }

    @Test("Malformed URL string passes through unchanged")
    func malformedURLPassesThrough() {
        let raw = "https://developer.apple.com/news/2026"
        // Has https:// but isn't a doc URL — returns raw, not nil.
        #expect(SUT.normalizeIdentifier(raw) == raw)
    }

    @Test("Empty string passes through unchanged")
    func emptyStringPassesThrough() {
        #expect(SUT.normalizeIdentifier("") == "")
    }

    @Test("http (not https) is also recognised")
    func plainHTTPIsAlsoRecognised() {
        let raw = "http://developer.apple.com/documentation/swiftui/view"
        #expect(SUT.normalizeIdentifier(raw) == "apple-docs://swiftui/view")
    }
}
