@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #1027 indexer dict registry-derivation pin

/// Pins the post-#1027 (Phase 1I.b of epic #1007) registry-derived
/// indexer dict shape: filter `allEnabled` by `destinationDB ==
/// .search`, then reduce to `[sourceID: any Search.SourceIndexer]`.
/// PackagesSource self-excludes because it declares `destinationDB
/// == .packages`; the search.db `Search.Index` only sees the 7
/// search.db indexers.
@Suite("#1027: indexer dict derived from registry filtered by destinationDB")
struct Issue1027IndexerDictRegistryDerivationTests {
    private static let derivedDict: [String: any Search.SourceIndexer] = CLIImpl.makeProductionSourceRegistry().allEnabled
        .filter { $0.destinationDB == .search }
        .reduce(into: [:]) { dict, provider in
            dict[provider.definition.id] = provider.makeIndexer()
        }

    @Test("Filtered dict contains exactly 7 entries (PackagesSource excluded because destinationDB == .packages)")
    func dictHasSevenSearchDBEntries() {
        #expect(Self.derivedDict.count == 7)
        let keys = Set(Self.derivedDict.keys)
        #expect(keys == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ])
    }

    @Test("PackagesSource is correctly self-excluded by destinationDB filter")
    func packagesSourceIsExcluded() {
        #expect(!Self.derivedDict.keys.contains(Shared.Constants.SourcePrefix.packages))
    }

    @Test("Each indexer's sourceID matches its dict key (no provider mis-keying)")
    func indexerSourceIDsMatchDictKeys() {
        for (key, indexer) in Self.derivedDict {
            #expect(indexer.sourceID == key, "Indexer for key \(key) has sourceID \(indexer.sourceID); they must match")
        }
    }

    @Test("PackagesSource is in the registry but excluded from the indexer dict (validates destinationDB protocol contract)")
    func registryHasEightProvidersDictHasSeven() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        #expect(registry.allEnabled.count == 8) // all 8 sources registered
        #expect(Self.derivedDict.count == 7) // search.db dispatch sees 7
        let packagesProvider = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.packages }
        #expect(packagesProvider?.destinationDB == .packages)
    }
}
