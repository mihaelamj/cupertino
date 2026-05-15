import Foundation
@testable import SearchToolProvider
import SharedConstants
import Testing

// MARK: - #587 — MCP read_document URI normalisation
//
// Mirrors the CLI side's `Services.ReadService.normalizeIdentifier`
// tests. Both transports must accept the same input shapes; this
// suite pins the MCP-side symmetric behaviour.

@Suite("CompositeToolProvider.normalizeReadDocumentURI (#587 web URL → URI)")
struct ReadDocumentURINormalizationTests {
    typealias SUT = CompositeToolProvider

    @Test("Canonical Apple Developer web URL → lossless apple-docs URI")
    func appleDeveloperWebURLConvertsToURI() {
        #expect(SUT.normalizeReadDocumentURI("https://developer.apple.com/documentation/swiftui/view")
            == "apple-docs://swiftui/view")
    }

    @Test("Mixed-case web URL lowercases")
    func mixedCaseLowercases() {
        #expect(SUT.normalizeReadDocumentURI("https://developer.apple.com/documentation/SwiftUI/View")
            == "apple-docs://swiftui/view")
    }

    @Test("Query + fragment stripped")
    func stripsQueryAndFragment() {
        #expect(SUT.normalizeReadDocumentURI("https://developer.apple.com/documentation/swiftui/view?language=swift#discussion")
            == "apple-docs://swiftui/view")
    }

    @Test("apple-docs URI passes through unchanged")
    func uriPassesThrough() {
        let raw = "apple-docs://swiftui/toolbarrole/navigationstack"
        #expect(SUT.normalizeReadDocumentURI(raw) == raw)
    }

    @Test("Non-Apple web URL passes through unchanged")
    func nonAppleURLPassesThrough() {
        let raw = "https://example.com/documentation/swiftui/view"
        #expect(SUT.normalizeReadDocumentURI(raw) == raw)
    }

    @Test("Framework-root web URL → framework-only URI")
    func frameworkRootURL() {
        #expect(SUT.normalizeReadDocumentURI("https://developer.apple.com/documentation/swiftui")
            == "apple-docs://swiftui")
    }

    @Test("Empty string passes through")
    func emptyPassesThrough() {
        #expect(SUT.normalizeReadDocumentURI("") == "")
    }
}
