@_spi(CupertinoInternal) import CupertinoComposition
import CupertinoDataEngine
import Foundation
import SharedConstants
import Testing

// MARK: - #1286 — the embedded (iOS) engine's per-source bundle carries the canonical docs source set

///
/// #1286 fixed the macOS `serve` path, which had searched only the apple-docs
/// primary DB. The OTHER desktop path is the embedded `CupertinoDataEngine`
/// (iOS). Reading the pinned dependency source (0.2.7) confirmed its unified
/// `search` fans across every per-source reader (`orderedSourceReaders()` +
/// `fuseResults`), so it does NOT share the serve bug. This boundary guard locks
/// that cupertino's embedded bundle CONFIGURATION still lists the full canonical
/// docs source set: a future `CupertinoDataEngine` bump that dropped a docs
/// source from `perSourceBundle` would silently shrink the iOS search surface,
/// and this test catches it at cupertino's dependency boundary without needing
/// a full on-disk corpus.
///
/// The engine keys docs corpus resources by SOURCE id (`apple-docs`, `hig`, …),
/// which for five of six coincides with the DB descriptor id; apple-docs is the
/// exception (source `apple-docs` vs descriptor `apple-documentation`).
@Suite("#1286 — embedded engine per-source docs bundle is the canonical set")
struct Issue1286EmbeddedEngineSourceSetTests {
    /// The canonical docs sources cupertino ships, by SOURCE id (the engine
    /// keys docs corpus resources by source prefix — `apple-docs`, not the
    /// `apple-documentation` DB descriptor id; the other five coincide).
    /// Mirrors the docs subset of #1282's canonical shipped set (sample-code +
    /// packages are configured as the engine's separate sample/package
    /// resources, not in `sourceCorpusResources`).
    private static let canonicalDocsSourceIDs: Set<String> = [
        Shared.Constants.SourcePrefix.appleDocs,
        Shared.Constants.SourcePrefix.hig,
        Shared.Constants.SourcePrefix.appleArchive,
        Shared.Constants.SourcePrefix.swiftEvolution,
        Shared.Constants.SourcePrefix.swiftOrg,
        Shared.Constants.SourcePrefix.swiftBook,
    ]

    @Test("the embedded per-source bundle config lists exactly the canonical docs source set")
    func embeddedBundleListsCanonicalDocsSources() {
        let config = CupertinoComposition.makePerSourceDataEngineConfiguration(
            corpusDirectory: URL(fileURLWithPath: "/tmp/cupertino-embedded-1286")
        )
        let ids = Set(config.sourceCorpusResources.map(\.id))

        // Exact equality: catches both a dropped docs source (iOS would lose it
        // from search, the #1286 failure mode) and an unexpected addition.
        #expect(ids == Self.canonicalDocsSourceIDs, "embedded bundle docs sources drifted from cupertino's canonical set: \(ids)")
    }
}
