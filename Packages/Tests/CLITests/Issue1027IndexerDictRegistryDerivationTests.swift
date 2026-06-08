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
/// == .packages`; the search.db `Search.Index` sees the registry entries
/// whose destination is not packages.
@Suite("#1027: indexer dict derived from registry filtered by destinationDB")
struct Issue1027IndexerDictRegistryDerivationTests {
    private static let derivedDict: [String: any Search.SourceIndexer] = CLIImpl.makeProductionSourceRegistry().allEnabled
        .filter { $0.destinationDB != .packages }
        .reduce(into: [:]) { dict, provider in
            dict[provider.definition.id] = provider.makeIndexer()
        }

    @Test("Filtered dict contains the built-in non-package entries")
    func dictHasBuiltInSearchDBEntries() {
        let keys = Set(Self.derivedDict.keys)
        #expect(keys.isSuperset(of: [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ]))
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
    func registryHasPackagesProviderButDictExcludesIt() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let packagesProvider = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.packages }
        #expect(packagesProvider?.destinationDB == .packages)
        #expect(!Self.derivedDict.keys.contains(Shared.Constants.SourcePrefix.packages))
    }
}
