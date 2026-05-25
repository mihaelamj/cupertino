@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - Per-source capabilities shape pin tests

//
// Step 3 of the per-source DB split epic (see
// `docs/design/per-source-db-split.md`): each Search.SourceProvider
// in the production registry now declares its capabilities matrix
// matching the YAML manifest at docs/sources/<sourceId>/manifest.yaml.
//
// These tests pin each source's Swift-side capability declaration so
// a rename or drop catches at this seam, not at step-4 dispatch time.
// Provider lookup goes through CLIImpl.makeProductionSourceRegistry()
// to avoid this test target needing direct deps on every per-source
// SPM target (each <X>Source lives in its own target).

@Suite("Per-source capabilities: each SourceProvider's declared matrix matches its manifest")
struct PerSourceCapabilitiesShapeTests {
    private func provider(forSourceId sourceId: String) -> any Search.SourceProvider {
        let registry = CLIImpl.makeProductionSourceRegistry()
        guard let entry = registry.allEnabled.first(where: { $0.definition.id == sourceId }) else {
            Issue.record("source '\(sourceId)' not in production registry")
            fatalError("source '\(sourceId)' missing from registry")
        }
        return entry
    }

    @Test("apple-docs: full apple-documentation capability matrix")
    func appleDocsCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.appleDocs).capabilities
        #expect(capabilities.searchers == [.text, .symbols, .propertyWrappers, .concurrency, .conformances, .generics])
        #expect(capabilities.operations == [.readByURI, .listFrameworks, .resolveRefs])
        #expect(capabilities.metadata[.hasMinPlatformVersion] == true)
        #expect(capabilities.metadata[.hasGenerics] == true)
        #expect(capabilities.metadata[.hasDeprecationAttrs] == true)
        #expect(capabilities.metadata[.hasAvailabilityAttrs] == true)
        #expect(capabilities.metadata[.hasFrameworkColumn] == true)
        #expect(capabilities.metadata[.hasMinSwiftVersion] == nil, "apple-docs does not declare Swift-version metadata")
        #expect(capabilities.metadata[.hasSampleCode] == nil)
    }

    @Test("hig: text-only, no framework column (matches production CandidateFetcher behavior)")
    func higCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.hig).capabilities
        #expect(capabilities.searchers == [.text])
        #expect(capabilities.operations == [.readByURI])
        #expect(capabilities.metadata[.hasMinPlatformVersion] == true)
        #expect(capabilities.metadata[.hasDeprecationAttrs] == true)
        #expect(capabilities.metadata[.hasAvailabilityAttrs] == true)
        #expect(capabilities.metadata[.hasFrameworkColumn] == nil, "HIG rows carry framework=\"\" per CandidateFetcher.frameworkScopedSources; flag MUST NOT be set")
        #expect(!capabilities.operations.contains(.listFrameworks), "HIG must not advertise list-frameworks")
    }

    @Test("apple-archive: list-frameworks supported (matches frameworkScopedSources)")
    func appleArchiveCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.appleArchive).capabilities
        #expect(capabilities.searchers == [.text])
        #expect(capabilities.operations == [.readByURI, .listFrameworks])
        #expect(capabilities.metadata[.hasMinPlatformVersion] == true)
        #expect(capabilities.metadata[.hasFrameworkColumn] == true, "apple-archive IS in CandidateFetcher.frameworkScopedSources")
    }

    @Test("swift-evolution: text + proposal-number + min-Swift-version")
    func swiftEvolutionCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.swiftEvolution).capabilities
        #expect(capabilities.searchers == [.text])
        #expect(capabilities.operations == [.readByURI])
        #expect(capabilities.metadata[.hasMinSwiftVersion] == true)
        #expect(capabilities.metadata[.hasProposalNumber] == true)
        #expect(capabilities.metadata[.hasFrameworkColumn] == nil)
    }

    @Test("swift-org: text + symbols + generics (covers swift-documentation.db rows post-step-4)")
    func swiftOrgCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.swiftOrg).capabilities
        #expect(capabilities.searchers == [.text, .symbols, .generics])
        #expect(capabilities.operations == [.readByURI])
        #expect(capabilities.metadata[.hasGenerics] == true)
        #expect(capabilities.metadata[.hasAvailabilityAttrs] == true)
    }

    @Test("swift-book: empty capabilities (view-source; swift-org carries the matrix for swift-documentation.db)")
    func swiftBookCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.swiftBook).capabilities
        #expect(capabilities.searchers.isEmpty, "swift-book is a view-source; capabilities live on the host SwiftOrgSource")
        #expect(capabilities.operations.isEmpty)
        #expect(capabilities.metadata.isEmpty)
    }

    @Test("samples: sample-files searcher + list-samples operation + hasSampleCode flag")
    func sampleCodeCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.samples).capabilities
        #expect(capabilities.searchers == [.text, .sampleFiles])
        #expect(capabilities.operations == [.readByURI, .listSamples])
        #expect(capabilities.metadata[.hasMinPlatformVersion] == true)
        #expect(capabilities.metadata[.hasSampleCode] == true)
    }

    @Test("packages: package-search searcher + hasPackageMetadata flag")
    func packagesCapabilities() {
        let capabilities = provider(forSourceId: Shared.Constants.SourcePrefix.packages).capabilities
        #expect(capabilities.searchers == [.text, .packageSearch])
        #expect(capabilities.operations == [.readByURI])
        #expect(capabilities.metadata[.hasMinSwiftVersion] == true)
        #expect(capabilities.metadata[.hasPackageMetadata] == true)
    }

    // MARK: - Cross-source invariants

    @Test("Every search-bound source declares at least the text searcher (the universal floor)")
    func everySearchBoundSourceHasTextSearcher() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let searchBound = registry.allEnabled.filter { $0.destinationDB.id == "search" }
        for provider in searchBound {
            // SwiftBookSource is the documented view-source exception (empty capabilities).
            if provider.definition.id == Shared.Constants.SourcePrefix.swiftBook {
                continue
            }
            #expect(
                provider.capabilities.searchers.contains(.text),
                "search-bound source '\(provider.definition.id)' must declare the .text searcher"
            )
        }
    }

    @Test("Capabilities.empty has no searchers / operations / metadata (dispatcher floor)")
    func capabilitiesEmptyIsTrulyEmpty() {
        let empty = Search.Capabilities.empty
        #expect(empty.searchers.isEmpty)
        #expect(empty.operations.isEmpty)
        #expect(empty.metadata.isEmpty)
    }
}
