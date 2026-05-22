import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #919 ironclad coverage pin: displayName regression guard for all 8 sources

@Suite("#919 ironclad: Search.Source.displayName regression guard")
struct Issue919DisplayNameRegressionTests {
    // Pin every historical source's displayName so a future PR that
    // renames an entry (e.g. "Swift Evolution" → "Swift Evolution
    // Proposals") surfaces here before it ships to MCP responses,
    // dashboard JSON, or `cupertino setup` final-summary output.
    //
    // Pre-#251 the displayName lived inside a closed switch on the
    // Source enum cases (which the test below would have pinned by
    // inspection). Post-#251 displayName is descriptor-backed via
    // `Search.SourceRegistry.definition(for: rawValue)?.displayName`;
    // a SourceRegistry row rename now bypasses any compile-time
    // guard, so this test is the only mechanical pin.

    @Test("apple-docs displayName")
    func appleDocs() {
        #expect(Search.Source.appleDocs.displayName == "Apple Documentation")
    }

    @Test("samples displayName")
    func samples() {
        #expect(Search.Source.samples.displayName == "Sample Code")
    }

    @Test("hig displayName")
    func hig() {
        #expect(Search.Source.hig.displayName == "Human Interface Guidelines")
    }

    @Test("apple-archive displayName preserves the `(Legacy)` suffix")
    func appleArchive() {
        // Pinned by the iter-2 critic on #924 (the enum-to-struct
        // collapse); the historical enum switch returned
        // "Apple Archive (Legacy)" but the SourceRegistry row had
        // "Apple Archive". #924 aligned the row to the enum's value
        // to preserve user-visible strings byte-identical pre/post.
        #expect(Search.Source.appleArchive.displayName == "Apple Archive (Legacy)")
    }

    @Test("swift-evolution displayName")
    func swiftEvolution() {
        #expect(Search.Source.swiftEvolution.displayName == "Swift Evolution")
    }

    @Test("swift-org displayName")
    func swiftOrg() {
        #expect(Search.Source.swiftOrg.displayName == "Swift.org")
    }

    @Test("swift-book displayName")
    func swiftBook() {
        #expect(Search.Source.swiftBook.displayName == "The Swift Programming Language")
    }

    @Test("packages displayName")
    func packages() {
        #expect(Search.Source.packages.displayName == "Swift Packages")
    }

    @Test("Emoji prefix regression guard for all 8 sources")
    func emojiPrefixesPinned() {
        // Same drift class as displayName; the per-source emoji is
        // user-visible in CLI / dashboard output and descriptor-backed
        // post-#251.
        #expect(Search.Source.appleDocs.emoji == "📘")
        #expect(Search.Source.samples.emoji == "💻")
        #expect(Search.Source.hig.emoji == "🎨")
        #expect(Search.Source.appleArchive.emoji == "📚")
        #expect(Search.Source.swiftEvolution.emoji == "🔮")
        #expect(Search.Source.swiftOrg.emoji == "🦅")
        #expect(Search.Source.swiftBook.emoji == "📖")
        #expect(Search.Source.packages.emoji == "📦")
    }
}
