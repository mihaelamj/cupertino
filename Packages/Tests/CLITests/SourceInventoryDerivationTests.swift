@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

/// The active-source inventory behind the `list_sources` MCP tool (#1277) must be derived from
/// the source registry (`bundleRequiredDescriptors`), so it is the canonical per-source set, the
/// legacy unified `search.db` is excluded, and it stays correct across the per-source-DB-split
/// migration (#1036) without a hardcoded list.
@Suite("CLIImpl.activeSourceInventory derivation (#1277)")
struct SourceInventoryDerivationTests {
    @Test("the inventory is exactly the registry-declared per-source descriptors")
    func inventoryMatchesBundleDescriptors() {
        let descriptors = CLIImpl.bundleRequiredDescriptors()
        let inventory = CLIImpl.activeSourceInventory()

        #expect(inventory.expected == descriptors.count)
        #expect(inventory.sources.map(\.id) == descriptors.map(\.id))
        #expect(inventory.sources.map(\.filename) == descriptors.map(\.filename))
    }

    @Test("the legacy unified search.db is never an active source")
    func legacySearchIsExcluded() {
        let inventory = CLIImpl.activeSourceInventory()
        let searchID = Shared.Models.DatabaseDescriptor.search.id
        #expect(!inventory.sources.contains { $0.id == searchID })
    }

    @Test("installed never exceeds expected, and isComplete agrees with the counts")
    func countsAreConsistent() {
        let inventory = CLIImpl.activeSourceInventory()
        #expect(inventory.installed <= inventory.expected)
        #expect(inventory.isComplete == (inventory.installed == inventory.expected))
    }
}
