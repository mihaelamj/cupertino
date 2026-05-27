// swiftlint:disable line_length
// (descriptive STATUS comments + path strings exceed the 120-char guideline)

@testable import CLI
import EnrichmentModels
import Foundation
import HIGSource
import SearchModels
import SharedConstants
import Testing

// MARK: - #1073 pluggability contract

//
// Two-layer contract pinning the docs-tier source-specific enrichment
// seam shipped in #1073:
//
// 1. STRUCTURAL: the protocol requirement
//    `Search.SourceProvider.makeSourceSpecificEnrichmentPasses` lives in
//    the protocol body (not extension-only). HIGSource overrides it
//    with a non-empty list; a vanilla provider returns the default
//    empty array. This pins both witness shapes against future drift.
//
// 2. PRODUCTION CALL-SITE: `CLIImpl.Command.Save.Indexers.swift`
//    iterates the providers and appends each provider's source-specific
//    passes into the docs-tier enrichment runner. A refactor that drops
//    the loop fails this assertion mechanically (mirrors the
//    `Issue1045ProductionCallSiteTests` pattern).
//
// Together: a future PR cannot silently regress the #1073 pluggability
// without one of these tests failing.

private struct EmptySourceSpecificFake: Search.SourceProvider {
    static let fakeID = "issue-1073-empty-source-specific-fake"

    let definition = Search.SourceDefinition(
        id: EmptySourceSpecificFake.fakeID,
        displayName: "Issue 1073 Empty Source-Specific Fake",
        emoji: "🧪",
        properties: Search.SourceProperties(
            authority: 0.5,
            freshness: 0.5,
            comprehensiveness: 0.5,
            codeExamples: 0.5,
            hasAvailability: 0.5,
            designFocus: 0.5,
            languageFocus: 0.5,
            searchQuality: 0.5
        ),
        intents: [.howTo]
    )

    var destinationDB: Shared.Models.DatabaseDescriptor {
        .swiftOrg
    }

    var fetchInfo: Search.FetchInfo? {
        nil
    }

    var capabilities: Search.Capabilities {
        Search.Capabilities(searchers: [.text], operations: [.readByURI])
    }

    var legacySourceIDAliases: Set<String> {
        []
    }

    func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        preconditionFailure("Contract test never invokes makeStrategy")
    }

    func makeIndexer() -> any Search.SourceIndexer {
        preconditionFailure("Contract test never invokes makeIndexer")
    }
}

@Suite("#1073 — docs-tier source-specific enrichment is pluggable end-to-end")
struct Issue1073PluggabilityContractTests {
    // MARK: - Layer 1: structural pin

    @Test("HIGSource overrides makeSourceSpecificEnrichmentPasses with at least one pass")
    func higSourceReturnsAtLeastOneSourceSpecificPass() {
        let provider = HIGSource()
        // We can't construct a real Search.Index in this test (no DB), so
        // we exercise the API surface that the composition root sees: the
        // factory returns a non-empty array carrying a HIG-tagged pass.
        // Passing `nil` for searchIndex/audit + an empty path is safe —
        // the factory just constructs the wrapper, it doesn't run SQL.
        let passes = provider.makeSourceSpecificEnrichmentPasses(
            searchIndex: NoopIndexWriter(),
            audit: nil,
            dbPath: ""
        )
        #expect(!passes.isEmpty, "HIGSource must return its platform-inference pass (#1073)")
        // The pass's identifier pins the wiring so a renamed pass is
        // caught at test time, not at next reindex.
        let identifiers = passes.map(\.identifier)
        #expect(identifiers.contains("hig-platforms"), "HIGSource must return the hig-platforms pass; got \(identifiers)")
    }

    @Test("Default extension returns empty array for providers that do not override")
    func defaultExtensionReturnsEmpty() {
        let fake = EmptySourceSpecificFake()
        let passes = fake.makeSourceSpecificEnrichmentPasses(
            searchIndex: NoopIndexWriter(),
            audit: nil,
            dbPath: ""
        )
        #expect(passes.isEmpty, "A provider that does not override must inherit the empty default ([])")
    }

    // MARK: - Layer 2: production call-site grep

    private static func workspaceRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let packages = dir.appendingPathComponent("Packages")
            if FileManager.default.fileExists(atPath: packages.path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/")
    }

    private static func sourceFile(_ relativePath: String) throws -> String {
        let url = workspaceRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("CLIImpl.Command.Save.Indexers.swift iterates providers and appends source-specific passes")
    func saveIndexersIteratesProviders() throws {
        let body = try Self.sourceFile("Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift")
        #expect(
            body.contains("provider.makeSourceSpecificEnrichmentPasses"),
            "Save.Indexers must invoke provider.makeSourceSpecificEnrichmentPasses on each docs-tier provider (#1073 pluggability)"
        )
        #expect(
            body.contains("passes.append(contentsOf: provider.makeSourceSpecificEnrichmentPasses"),
            "Save.Indexers must append the provider's source-specific passes into the docs-tier enrichment list"
        )
        // Pluggability invariant: no per-source descriptor.id == .hig
        // conditional should appear in this file. If a future PR adds
        // one, the seam is being bypassed.
        #expect(
            !body.contains("descriptor.id == Shared.Models.DatabaseDescriptor.hig.id"),
            "Save.Indexers must not branch on descriptor.id == .hig; source-specific passes belong on the SourceProvider (#1073)"
        )
        // CLI must not import HIG-specific enrichment modules directly.
        #expect(
            !body.contains("import HIGPlatformInferencePass"),
            "CLI Save.Indexers must not import HIGPlatformInferencePass directly; the module transits via HIGSource's deps (#1073)"
        )
    }
}

// MARK: - Test fixture

/// Minimal IndexWriter conformer used only as a typed slot for the
/// pluggability factory exercise. It is never asked to do real work;
/// the test only inspects the array of passes the provider returns.
/// Every protocol method preconditionFails — if a test path reaches
/// one, the test setup is wrong.
private struct NoopIndexWriter: Search.IndexWriter {
    func indexDocument(_: Search.IndexDocumentParams) async throws {
        preconditionFailure("NoopIndexWriter.indexDocument should not be invoked by the pluggability contract test")
    }

    func indexStructuredDocument(
        uri _: String,
        source _: String,
        framework _: String,
        page _: Shared.Models.StructuredDocumentationPage,
        jsonData _: String,
        overrideMinIOS _: String?,
        overrideMinMacOS _: String?,
        overrideMinTvOS _: String?,
        overrideMinWatchOS _: String?,
        overrideMinVisionOS _: String?,
        overrideAvailabilitySource _: String?,
        implementationSwiftVersion _: String?
    ) async throws {
        preconditionFailure("NoopIndexWriter.indexStructuredDocument should not be invoked by the pluggability contract test")
    }

    func indexSampleCode(
        url _: String,
        framework _: String,
        title _: String,
        description _: String,
        zipFilename _: String,
        webURL _: String,
        minIOS _: String?,
        minMacOS _: String?,
        minTvOS _: String?,
        minWatchOS _: String?,
        minVisionOS _: String?
    ) async throws {
        preconditionFailure("NoopIndexWriter.indexSampleCode should not be invoked by the pluggability contract test")
    }

    func indexCodeExamples(docUri _: String, codeExamples _: [(code: String, language: String)]) async throws {
        preconditionFailure("NoopIndexWriter.indexCodeExamples should not be invoked by the pluggability contract test")
    }

    func extractCodeExampleSymbols(docUri _: String, codeExamples _: [(code: String, language: String)]) async throws {
        preconditionFailure("NoopIndexWriter.extractCodeExampleSymbols should not be invoked by the pluggability contract test")
    }

    func registerFrameworkAlias(identifier _: String, displayName _: String) async throws {
        preconditionFailure("NoopIndexWriter.registerFrameworkAlias should not be invoked by the pluggability contract test")
    }

    func updateFrameworkSynonyms(identifier _: String, synonyms _: String) async throws {
        preconditionFailure("NoopIndexWriter.updateFrameworkSynonyms should not be invoked by the pluggability contract test")
    }

    func applyAppleStaticConstraints(
        lookup _: (any Search.StaticConstraintsLookup)?,
        audit _: (any Search.EnrichmentAuditObserver)?,
        dbPath _: String
    ) async throws -> Int {
        preconditionFailure("NoopIndexWriter.applyAppleStaticConstraints should not be invoked by the pluggability contract test")
    }

    func propagateConstraintsFromParents(
        audit _: (any Search.EnrichmentAuditObserver)?,
        dbPath _: String
    ) async throws -> Int {
        preconditionFailure("NoopIndexWriter.propagateConstraintsFromParents should not be invoked by the pluggability contract test")
    }

    func applyHIGPlatformInference(
        audit _: (any Search.EnrichmentAuditObserver)?,
        dbPath _: String
    ) async throws -> Int {
        preconditionFailure("NoopIndexWriter.applyHIGPlatformInference should not be invoked by the pluggability contract test")
    }

    func clearIndex() async throws {
        preconditionFailure("NoopIndexWriter.clearIndex should not be invoked by the pluggability contract test")
    }
}
