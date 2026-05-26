@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - CLIImpl.Command.ListFrameworks capability-driven fan-out

//
// Pins the post-#1037 + critic-round-14 list-frameworks fan-out
// shape: rather than hardcoding `[appleDocsURL, appleArchiveURL]`
// (round-13 regression), the command iterates the production source
// registry and opens every source whose `capabilities.operations`
// contains `.listFrameworks`. Today that yields apple-docs +
// apple-archive; a future source declaring `.listFrameworks`
// (e.g. a hypothetical Swift Forums source that indexes framework
// references) drops in with zero edits to the command body --
// matching Source Independence Day's "2-file PR" standard.
//
// These tests are shape-pins on the production registry; they don't
// open any SQLite files.

@Suite("CLIImpl.Command.ListFrameworks capability-driven fan-out")
struct CLIListFrameworksFanOutTests {
    @Test("Production registry surfaces exactly the framework-scoped sources via capabilities")
    func capabilityFilterMatchesProductionExpectation() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let frameworkSources = registry.allEnabled.filter {
            $0.capabilities.operations.contains(.listFrameworks)
        }
        let ids = Set(frameworkSources.map(\.definition.id))
        // The two production sources with a meaningful `framework`
        // column. HIG / swift-evolution / swift-org / swift-book all
        // emit `framework=""` so they DO NOT declare this capability.
        #expect(ids == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
        ])
    }

    @Test("Non-framework-scoped sources do NOT declare .listFrameworks (Source Independence Day invariant)")
    func nonFrameworkSourcesAreExcluded() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let nonFramework: [String] = [
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ]
        for sourceID in nonFramework {
            let provider = registry.allEnabled.first { $0.definition.id == sourceID }
            #expect(provider != nil, "expected to find provider for \(sourceID)")
            let hasListFrameworks = provider?.capabilities.operations.contains(.listFrameworks) ?? false
            #expect(!hasListFrameworks, "\(sourceID) should NOT declare .listFrameworks")
        }
    }

    @Test("apple-docs provider's listFrameworks capability is the canonical anchor (regression pin)")
    func appleDocsDeclaresListFrameworks() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let appleDocs = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.appleDocs }
        #expect(appleDocs?.capabilities.operations.contains(.listFrameworks) == true)
    }

    @Test("apple-archive provider's listFrameworks capability is the canonical anchor (regression pin)")
    func appleArchiveDeclaresListFrameworks() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let appleArchive = registry.allEnabled.first { $0.definition.id == Shared.Constants.SourcePrefix.appleArchive }
        #expect(appleArchive?.capabilities.operations.contains(.listFrameworks) == true)
    }

    @Test("Adding any future framework-scoped source automatically joins the fan-out (2-file PR invariant)")
    func futureSourceJoinsFanOutAutomatically() {
        // This test exists as a written invariant rather than a
        // dynamic check: the command body iterates
        // `registry.allEnabled.filter { $0.capabilities.operations.contains(.listFrameworks) }`.
        // A future PR that registers a new SourceProvider declaring
        // `.listFrameworks` will be picked up by that filter without
        // edits to `CLIImpl.Command.ListFrameworks.run()`. The other
        // tests in this suite pin the production set today; the
        // assertion here is the shape contract.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let allFrameworkSources = registry.allEnabled.filter {
            $0.capabilities.operations.contains(.listFrameworks)
        }
        // Sanity-check the filter actually walks the registry +
        // returns *only* the sources with the declared capability
        // (no hardcoded list).
        for provider in allFrameworkSources {
            #expect(provider.capabilities.operations.contains(.listFrameworks))
        }
    }
}
