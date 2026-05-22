import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - #919 ironclad coverage pin: SourceRegistry row count

@Suite("#919 ironclad: SourceRegistry.all silent-row-add guard")
struct Issue919SourceRegistryCountTests {
    @Test("SourceRegistry.all has exactly 8 rows (the documented historical-source count)")
    func registryCountIsEight() {
        // Pin the SourceRegistry row count so a future PR that ADDS a
        // SourceDefinition without also adding a corresponding
        // `Search.Source.<name>` static constant surfaces here.
        //
        // The 8 historical sources are documented in
        // `docs/portability.md` and `docs/package-import-contract.md`.
        // The Issue919SourceAliasCoverageTests test
        // `registryIsReachableViaConstants` separately pins that each
        // of the 8 Search.Source static constants resolves to a
        // registered row, so a SourceDefinition deletion is also
        // guarded.
        //
        // To register a new source post-#919: add the SourcePrefix
        // constant + the SourceDefinition row + the Search.Source
        // static constant in lockstep. This test (`== 8`) ensures the
        // row count stays in sync with the static-constant count, so
        // a partial addition fails CI.
        #expect(
            Search.SourceRegistry.all.count == 8,
            """
            SourceRegistry.all.count drifted. Adding a row here requires \
            a matching Search.Source.<name> static constant in \
            Search.DomainTypes.swift AND a Shared.Constants.SourcePrefix.<name> \
            constant in Shared.Constants.swift. Bump this expected count \
            to match only after all three are in lockstep.
            """
        )
    }

    @Test("Every SourceRegistry.all row has a non-empty id and displayName")
    func everyRowHasIdentityFields() {
        // Pin that no row ships with empty identity bits. A row with
        // empty `id` would silently fail SourcePrefix matching; an
        // empty `displayName` would break MCP / dashboard formatting.
        for definition in Search.SourceRegistry.all {
            #expect(!definition.id.isEmpty, "SourceDefinition.id must not be empty")
            #expect(!definition.displayName.isEmpty, "SourceDefinition.displayName must not be empty for \(definition.id)")
            #expect(!definition.emoji.isEmpty, "SourceDefinition.emoji must not be empty for \(definition.id)")
        }
    }

    @Test("SourceRegistry.all has no duplicate ids")
    func everyIdIsUnique() {
        // Pin uniqueness: a duplicate id would mean
        // `SourceRegistry.definition(for: id)` is ambiguous (first
        // wins via firstIndex) and the second row is unreachable.
        let ids = Search.SourceRegistry.all.map(\.id)
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == ids.count, "Duplicate SourceDefinition.id found: \(ids)")
    }
}
