import Diagnostics
import Foundation
import SearchModels
import SharedConstants

extension CLIImpl {
    /// Build the canonical active-source inventory consumed by the `list_sources` MCP tool
    /// (#1277). The set of sources is `bundleRequiredDescriptors()` (the registry-declared
    /// per-source databases) so it excludes the legacy unified `search.db`, stays correct across
    /// the per-source-DB-split migration (#1036), and cannot drift from what `setup` extracts and
    /// the bundle ships. Each descriptor is annotated with on-disk presence and schema version.
    ///
    /// The schema version comes from `PRAGMA user_version`, except `apple-sample-code.db`, which
    /// stamps its version in a `samples_schema_version` table (the file-level PRAGMA is left for
    /// the Search.Index FTS track), matching how `doctor` reads it.
    static func activeSourceInventory(paths: Shared.Paths = .live()) -> Search.SourceInventory {
        let samplesID = Shared.Models.DatabaseDescriptor.appleSampleCode.id
        // Iterate the registry's providers (not just their `destinationDB` descriptors) so each
        // row carries its routing `sourceID` (`provider.definition.id`) alongside the descriptor
        // id — the additive enabler that lets a consumer map a source without hardcoding.
        let items = makeProductionSourceRegistry().allEnabled.map { provider -> Search.SourceInventoryItem in
            let descriptor = provider.destinationDB
            let url = paths.baseDirectory.appendingPathComponent(descriptor.filename)
            let present = FileManager.default.fileExists(atPath: url.path)
            let version: Int32 = descriptor.id == samplesID
                ? (Diagnostics.Probes.samplesSchemaVersion(at: url) ?? 0)
                : (Diagnostics.Probes.userVersion(at: url) ?? 0)
            return Search.SourceInventoryItem(
                id: descriptor.id,
                sourceID: provider.definition.id,
                displayName: descriptor.displayName,
                filename: descriptor.filename,
                present: present,
                schemaVersion: Int(version)
            )
        }
        return Search.SourceInventory(sources: items)
    }
}
