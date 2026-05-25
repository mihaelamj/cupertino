@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #1025 sourceLookup registry-derivation pin

/// Pins that `Search.SourceLookup` is now derived from the per-source
/// registry (post-#1025 / Phase 1I.a of epic #1007). Before this PR
/// the lookup was an inline 8-entry SourceDefinition literal list in
/// the deleted `CLIImpl.SourceLookup.swift`. Post-PR the lookup
/// definitions ARE the per-source targets' `.definition` static
/// literals; this test pins that derivation produces an
/// equivalent-shaped lookup (8 sources, expected ids, display-names
/// matching the deleted literal list's canonical values).
@Suite("#1025: SourceLookup derived from registry")
struct Issue1025SourceLookupRegistryDerivationTests {
    private static let derived: Search.SourceLookup = .init(
        definitions: CLIImpl.makeProductionSourceRegistry().allEnabled.map(\.definition)
    )

    @Test("Registry-derived lookup contains exactly 8 definitions matching the per-source targets")
    func derivedLookupCarriesAllEight() {
        #expect(Self.derived.definitions.count == 8)

        let ids = Set(Self.derived.allIDs)
        #expect(ids == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.samples,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
            Shared.Constants.SourcePrefix.packages,
        ])
    }

    @Test("Registry-derived lookup display-names match the deleted-literal-list canonical values")
    func displayNamesMatchPreDissolutionLiterals() {
        // The deleted `CLIImpl.makeProductionSourceLookup` factory
        // shipped these display-names verbatim; the post-#1025
        // per-source target's static `.definition.displayName` must
        // produce the same string for every id so the user-visible
        // label stays stable across the dissolution.
        #expect(Self.derived.displayName(for: .appleDocs) == "Apple Documentation")
        #expect(Self.derived.displayName(for: .hig) == "Human Interface Guidelines")
        #expect(Self.derived.displayName(for: .samples) == "Sample Code")
        #expect(Self.derived.displayName(for: .appleArchive) == "Apple Archive (Legacy)")
        #expect(Self.derived.displayName(for: .swiftEvolution) == "Swift Evolution")
        #expect(Self.derived.displayName(for: .swiftOrg) == "Swift.org")
        #expect(Self.derived.displayName(for: .swiftBook) == "The Swift Programming Language")
        #expect(Self.derived.displayName(for: .packages) == "Swift Packages")
    }

    @Test("Registry insertion order matches the production lookup order (deterministic dispatch)")
    func registryOrderMatchesLookupOrder() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let registryOrder = registry.allEnabled.map(\.definition.id)
        let lookupOrder = Self.derived.definitions.map(\.id)
        #expect(registryOrder == lookupOrder)
    }
}
