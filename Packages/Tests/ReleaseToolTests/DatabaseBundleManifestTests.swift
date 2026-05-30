import CupertinoComposition
@testable import ReleaseTool
import SearchModels
import SharedConstants
import Testing

// MARK: - Database bundle manifest drift guard (#1071)

// The per-source DB bundle that `cupertino-rel databases` ships must be
// derived from the production source registry, never a hardcoded filename
// list. These tests pin that contract: the bundle manifest equals the
// registry-derived descriptor set (so a new source auto-extends the bundle),
// and the stray pre-split `search.db` (which no enabled source declares as
// its destination) is never bundled.

@Suite("Database bundle manifest")
struct DatabaseBundleManifestTests {
    @Test("Bundled descriptors match the registry-derived manifest (no drift)")
    func bundledDescriptorsMatchRegistry() {
        let bundled = Release.Command.Database.bundledDescriptors().map(\.filename)

        // Independently re-derive the expected manifest the same way
        // `cupertino setup` does via `CLIImpl.bundleRequiredDescriptors()`:
        // every enabled source's `destinationDB`, deduped by filename with
        // stable first-seen order.
        let derived = CupertinoComposition.makeProductionSourceRegistry()
            .allEnabled
            .map(\.destinationDB.filename)
        var seen = Set<String>()
        let expected = derived.filter { seen.insert($0).inserted }

        #expect(bundled == expected)
    }

    @Test("Stray legacy search.db is never bundled (per-source split)")
    func legacySearchDatabaseExcluded() {
        let descriptors = Release.Command.Database.bundledDescriptors()
        let filenames = Set(descriptors.map(\.filename))

        // The pre-split unified index file has no enabled source backing it.
        #expect(!filenames.contains(Shared.Constants.FileName.searchDatabase))
        // The manifest is non-empty and free of duplicate filenames.
        #expect(!descriptors.isEmpty)
        #expect(filenames.count == descriptors.count)
    }
}
