@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #919 + #934 ironclad: production display-name + emoji regression pins

@Suite("#919 production display-name regression guard (post-#934)")
struct Issue919DisplayNameProductionTests {
    /// Post-#1025 (Phase 1I.a of #1007): production SourceLookup is
    /// derived from the per-source registry rather than the dissolved
    /// `makeProductionSourceLookup` inline literal list. The
    /// definitions are the per-source targets' static `.definition`
    /// literals (e.g. `AppleDocsSource.definition`).
    private static let production: Search.SourceLookup = .init(
        definitions: CLIImpl.makeProductionSourceRegistry().allEnabled.map(\.definition)
    )

    @Test("All built-in historical sources have non-empty display names + emojis in the production lookup")
    func allHistoricalSourcesAreRegistered() {
        let historical: [Search.Source] = [
            .appleDocs, .samples, .hig, .appleArchive,
            .swiftEvolution, .swiftOrg, .swiftBook, .packages,
        ]
        for source in historical {
            #expect(Self.production.isRegistered(source), "\(source.rawValue) must be in the production lookup")
            #expect(!Self.production.displayName(for: source).isEmpty)
            #expect(!Self.production.emoji(for: source).isEmpty)
        }
    }

    @Test("Production display names match the user-visible labels documented in MCP responses and footer formatters")
    func displayNamesPin() {
        let lookup = Self.production
        #expect(lookup.displayName(for: .appleDocs) == "Apple Documentation")
        #expect(lookup.displayName(for: .samples) == "Sample Code")
        #expect(lookup.displayName(for: .hig) == "Human Interface Guidelines")
        #expect(lookup.displayName(for: .appleArchive) == "Apple Archive (Legacy)")
        #expect(lookup.displayName(for: .swiftEvolution) == "Swift Evolution")
        #expect(lookup.displayName(for: .swiftOrg) == "Swift.org")
        #expect(lookup.displayName(for: .swiftBook) == "The Swift Programming Language")
        #expect(lookup.displayName(for: .packages) == "Swift Packages")
    }

    @Test("Production emojis match the user-visible glyphs documented for each source")
    func emojisPin() {
        let lookup = Self.production
        #expect(lookup.emoji(for: .appleDocs) == "📘")
        #expect(lookup.emoji(for: .samples) == "💻")
        #expect(lookup.emoji(for: .hig) == "🎨")
        #expect(lookup.emoji(for: .appleArchive) == "📚")
        #expect(lookup.emoji(for: .swiftEvolution) == "🔮")
        #expect(lookup.emoji(for: .swiftOrg) == "🦅")
        #expect(lookup.emoji(for: .swiftBook) == "📖")
        #expect(lookup.emoji(for: .packages) == "📦")
    }

    @Test("Production lookup carries at least the built-in historical sources")
    func productionLookupCarriesHistoricalSources() {
        let ids = Set(Self.production.allIDs)
        #expect(ids.isSuperset(of: [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
        ]))
    }

    @Test("Production lookup has no duplicate ids")
    func productionLookupHasNoDuplicateIds() {
        let ids = Self.production.allIDs
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Production lookup must have unique source ids; found duplicates in \(ids)")
    }

    @Test("Built-in production source ids match SourcePrefix constants")
    func builtInProductionIdsAreSourcePrefixConstants() {
        let validPrefixes: Set<String> = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
        ]
        let productionIDs = Set(Self.production.allIDs)
        for prefix in validPrefixes {
            #expect(productionIDs.contains(prefix), "\(prefix) must be registered in the production lookup")
        }
    }
}
