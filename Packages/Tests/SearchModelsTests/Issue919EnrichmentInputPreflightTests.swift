import AppleDocsSource
import Foundation
import HIGSource
import PackagesSource
import SampleCodeSource
import SearchModels
import SharedConstants
import Testing

// MARK: - #919 declarative enrichment-input preflight

/// Pins the declarative enrichment-input model that replaced the two hardcoded
/// per-source guards (the #1072 `apple-constraints.json` check and
/// `assertPackageAvailabilityComplete`). The Source Independence Axiom requires
/// each source to DECLARE its inputs (`SourceDefinition.requiredEnrichmentInputs`)
/// and one generic preflight (`Search.EnrichmentInputPreflight`) to enforce them
/// with no per-source branch.
@Suite("#919: declarative enrichment-input preflight")
struct Issue919EnrichmentInputPreflightTests {
    // MARK: Fixtures

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-preflight-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Synthetic definition that borrows real `SourceProperties` so the test
    /// does not couple to the `SourceProperties` initializer shape.
    private func definition(id: String, inputs: [Search.EnrichmentInput]) -> Search.SourceDefinition {
        Search.SourceDefinition(
            id: id,
            displayName: id,
            emoji: "x",
            properties: AppleDocsSource.definition.properties,
            intents: [],
            requiredEnrichmentInputs: inputs
        )
    }

    private func touch(_ url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: Data("{}".utf8))
    }

    // MARK: baseDirectoryFile scope

    @Test("baseDirectoryFile: an absent file is reported")
    func baseFileMissing() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [definition(id: "apple-docs", inputs: [.appleConstraints])],
            baseDirectory: base,
            corpusDirectoryByID: [:]
        )
        #expect(missing.count == 1)
        #expect(missing.first?.sourceID == "apple-docs")
        #expect(missing.first?.input == .appleConstraints)
        #expect(missing.first?.itemsMissing == nil)
    }

    @Test("baseDirectoryFile: a present file is not reported")
    func baseFilePresent() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        touch(base.appendingPathComponent("apple-constraints.json"))

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [definition(id: "apple-docs", inputs: [.appleConstraints])],
            baseDirectory: base,
            corpusDirectoryByID: [:]
        )
        #expect(missing.isEmpty)
    }

    // MARK: perCorpusItem scope

    @Test("perCorpusItem: a package missing its sidecar is reported with counts")
    func perItemMissing() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let corpus = base.appendingPathComponent("packages", isDirectory: true)
        let repoA = corpus.appendingPathComponent("owner/repoA", isDirectory: true)
        let repoB = corpus.appendingPathComponent("owner/repoB", isDirectory: true)
        try? FileManager.default.createDirectory(at: repoA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)
        touch(repoA.appendingPathComponent("manifest.json"))
        touch(repoA.appendingPathComponent("availability.json"))
        touch(repoB.appendingPathComponent("manifest.json")) // no availability.json sidecar

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [definition(id: "packages", inputs: [.packageAvailability])],
            baseDirectory: base,
            corpusDirectoryByID: ["packages": corpus]
        )
        #expect(missing.count == 1)
        #expect(missing.first?.input == .packageAvailability)
        #expect(missing.first?.itemsMissing == 1)
        #expect(missing.first?.itemsTotal == 2)
    }

    @Test("perCorpusItem: all sidecars present is not reported")
    func perItemComplete() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let corpus = base.appendingPathComponent("packages", isDirectory: true)
        let repo = corpus.appendingPathComponent("owner/repo", isDirectory: true)
        try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        touch(repo.appendingPathComponent("manifest.json"))
        touch(repo.appendingPathComponent("availability.json"))

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [definition(id: "packages", inputs: [.packageAvailability])],
            baseDirectory: base,
            corpusDirectoryByID: ["packages": corpus]
        )
        #expect(missing.isEmpty)
    }

    @Test("perCorpusItem: a nested file sharing the marker name is not a separate item")
    func perItemNestedMarkerPruned() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let corpus = base.appendingPathComponent("packages", isDirectory: true)
        let repo = corpus.appendingPathComponent("owner/repo", isDirectory: true)
        try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        touch(repo.appendingPathComponent("manifest.json"))
        touch(repo.appendingPathComponent("availability.json"))
        // A test fixture deep inside the package that is also named
        // `manifest.json` and has no availability.json sidecar. The recursive
        // pre-fix walk flagged this as a package missing its sidecar; the
        // pruning walk must treat it as part of the enclosing package.
        let fixtureDir = repo.appendingPathComponent("Tests/RepoTests/Manifests", isDirectory: true)
        try? FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        touch(fixtureDir.appendingPathComponent("manifest.json"))

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [definition(id: "packages", inputs: [.packageAvailability])],
            baseDirectory: base,
            corpusDirectoryByID: ["packages": corpus]
        )
        #expect(missing.isEmpty)
    }

    @Test("perCorpusItem: an absent corpus directory is skipped, not failed")
    func perItemNoCorpus() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [definition(id: "packages", inputs: [.packageAvailability])],
            baseDirectory: base,
            corpusDirectoryByID: [:] // packages corpus not present on disk this run
        )
        #expect(missing.isEmpty)
    }

    // MARK: Operator-facing messages

    @Test("failure message names the file, the fix command, and the degraded opt-out, with no em-dash")
    func messageContent() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [definition(id: "apple-docs", inputs: [.appleConstraints])],
            baseDirectory: base,
            corpusDirectoryByID: [:]
        )
        let message = Search.EnrichmentInputPreflight.failureMessage(missing)
        #expect(message.contains("apple-constraints.json"))
        #expect(message.contains("--allow-degraded-enrichment"))
        #expect(message.contains("cupertino setup") || message.contains("cupertino-constraints-gen"))
        #expect(!message.contains("\u{2014}")) // em-dash prohibition
    }

    // MARK: Real per-source declarations

    @Test("apple-docs and samples declare constraints + conformances; packages declares those plus availability")
    func realDeclarations() {
        #expect(AppleDocsSource.definition.requiredEnrichmentInputs == [.appleConstraints, .appleConformances])
        #expect(SampleCodeSource.definition.requiredEnrichmentInputs == [.appleConstraints, .appleConformances])
        #expect(
            PackagesSource.definition.requiredEnrichmentInputs
                == [.appleConstraints, .appleConformances, .packageAvailability]
        )
    }

    @Test("apple-conformances.json absence is reported for every source that runs a conformance pass (#1144)")
    func conformancesMissingReportedPerSource() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        // Neither constraints nor conformances present in the base dir.
        for source in [AppleDocsSource.definition, SampleCodeSource.definition, PackagesSource.definition] {
            let missing = Search.EnrichmentInputPreflight.missing(
                definitions: [source],
                baseDirectory: base,
                corpusDirectoryByID: [:]
            )
            #expect(
                missing.contains { $0.input == .appleConformances },
                "\(source.id) must flag a missing apple-conformances.json"
            )
        }
    }

    @Test("present apple-conformances.json clears the conformance requirement")
    func conformancesPresentNotReported() {
        let base = makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        touch(base.appendingPathComponent("apple-constraints.json"))
        touch(base.appendingPathComponent("apple-conformances.json"))

        let missing = Search.EnrichmentInputPreflight.missing(
            definitions: [AppleDocsSource.definition],
            baseDirectory: base,
            corpusDirectoryByID: [:]
        )
        #expect(missing.isEmpty)
    }

    @Test("a source with no enrichment input requirement declares none")
    func noInputsSource() {
        #expect(HIGSource.definition.requiredEnrichmentInputs.isEmpty)
    }
}
