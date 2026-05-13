import SearchModels
import Foundation
@testable import Search
import SharedCore
import Testing

// Truth-table coverage for `Search.AppleDocsIndexer.validate(_:)`. The function was
// rewritten in PR #288 from
//
//   item.framework != nil && !item.framework!.isEmpty
//
// to the optional-aware form
//
//   item.framework?.isEmpty == false
//
// These tests pin the four-branch truth table so future edits to the
// validator can't silently change which items are accepted.

@Suite("Search.AppleDocsIndexer.validate")
struct AppleDocsIndexerValidateTests {
    private static func item(
        uri: String = "apple-docs://swiftui/view",
        title: String = "View",
        framework: String? = "swiftui"
    ) -> Search.SourceItem {
        Search.SourceItem(
            uri: uri,
            source: "apple-docs",
            title: title,
            content: "",
            filePath: "",
            contentHash: "",
            framework: framework
        )
    }

    private let indexer = Search.AppleDocsIndexer()

    // MARK: framework field

    @Test("rejects an item whose framework is nil")
    func rejectsNilFramework() {
        #expect(indexer.validate(Self.item(framework: nil)) == false)
    }

    @Test("rejects an item whose framework is the empty string")
    func rejectsEmptyFramework() {
        #expect(indexer.validate(Self.item(framework: "")) == false)
    }

    @Test("accepts an item with a non-empty framework + non-empty uri/title")
    func acceptsHappyPath() {
        #expect(indexer.validate(Self.item(framework: "swiftui")) == true)
    }

    // MARK: uri / title fields (the && chain partners)

    @Test("rejects an item whose uri is empty even with a valid framework")
    func rejectsEmptyURI() {
        #expect(indexer.validate(Self.item(uri: "", framework: "swiftui")) == false)
    }

    @Test("rejects an item whose title is empty even with a valid framework")
    func rejectsEmptyTitle() {
        #expect(indexer.validate(Self.item(title: "", framework: "swiftui")) == false)
    }

    @Test("accepts a single-character framework string (boundary)")
    func acceptsSingleCharFramework() {
        // The validator only checks isEmpty — any non-empty string passes,
        // even one that wouldn't be a real Apple framework name. Pinning
        // the boundary so an "improvement" to add length-checking is a
        // conscious decision, not an accident.
        #expect(indexer.validate(Self.item(framework: "x")) == true)
    }
}
