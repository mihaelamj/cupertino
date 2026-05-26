@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - CLIImpl.resolveAppleDocsDBURL

//
// Pins the post-#1037 apple-docs DB URL resolution shared by every
// AST-aware CLI subcommand (`cupertino search-symbols` /
// `inheritance` / `search-conformances` / `search-concurrency` /
// `search-property-wrappers` / `search-generics` / `list-frameworks`).
// Pre-#1037 each command independently fell back to
// `Shared.Paths.live().searchDatabase` (the legacy monolithic
// `search.db`); post-#1037 the canonical location is
// `apple-documentation.db` (the descriptor's `filename`).
//
// The helper is pure: it routes through the production source
// registry's `AppleDocsSource.destinationDB.filename` so a future
// rename of the descriptor's filename flows through here with zero
// edits to the 7 consumer commands.

@Suite("CLIImpl.resolveAppleDocsDBURL")
struct CLIAppleDocsDBURLTests {
    @Test("With no override, resolves to apple-documentation.db under the live base directory")
    func defaultResolvesToAppleDocumentation() {
        let url = CLIImpl.resolveAppleDocsDBURL()
        #expect(url.lastPathComponent == Shared.Models.DatabaseDescriptor.appleDocumentation.filename)
        // Specifically: NOT `search.db` (the legacy descriptor).
        #expect(url.lastPathComponent != Shared.Constants.FileName.searchDatabase)
    }

    @Test("With override, returns the override URL verbatim")
    func overrideWinsOverDefault() {
        let url = CLIImpl.resolveAppleDocsDBURL(override: "/tmp/custom/db.sqlite")
        #expect(url.path == "/tmp/custom/db.sqlite")
        #expect(url.lastPathComponent == "db.sqlite")
    }

    @Test("Override expands the tilde so `~/foo.db` resolves to the home directory")
    func overrideExpandsTilde() {
        let url = CLIImpl.resolveAppleDocsDBURL(override: "~/cup-test.db")
        #expect(url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
        #expect(url.lastPathComponent == "cup-test.db")
        #expect(!url.path.contains("~"))
    }

    @Test("Production registry round-trip: resolved filename matches AppleDocsSource.destinationDB")
    func productionRegistryRoundTrip() {
        // The whole point of routing through `makeProductionSourceRegistry`
        // instead of hardcoding the filename is that
        // `AppleDocsSource.destinationDB.filename` is the canonical
        // mapping. A future PR that flipped `AppleDocsSource.destinationDB`
        // to a different descriptor would flow through here without
        // touching the helper.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let appleDocs = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.appleDocs }
        #expect(appleDocs != nil)
        let url = CLIImpl.resolveAppleDocsDBURL()
        #expect(url.lastPathComponent == appleDocs?.destinationDB.filename)
    }

    @Test("Nil and absent override are equivalent")
    func nilAndAbsentOverrideAreEquivalent() {
        let urlA = CLIImpl.resolveAppleDocsDBURL()
        let urlB = CLIImpl.resolveAppleDocsDBURL(override: nil)
        #expect(urlA.path == urlB.path)
    }
}
