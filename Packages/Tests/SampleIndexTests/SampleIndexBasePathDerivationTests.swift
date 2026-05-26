import Foundation
@testable import SampleIndex
import SharedConstants
import Testing

/// Companion to `BasePathDerivationTests` in SharedTests, covering the
/// SampleIndex-side path builders. Post-#535 the static-default accessors
/// (`Shared.Constants.defaultBaseDirectory`, `Sample.Index.defaultDatabasePath`,
/// `Sample.Index.defaultSampleCodeDirectory`) are gone — they routed through
/// the `BinaryConfig.shared` Singleton (Service Locator). The replacement is
/// `Sample.Index.databasePath(baseDirectory:)` / `sampleCodeDirectory(baseDirectory:)`,
/// which take an explicit base directory threaded from the composition root.
@Suite("SampleIndex path builders derive from explicit baseDirectory (#535)")
struct SampleIndexBasePathDerivationTests {
    private let base = URL(fileURLWithPath: "/tmp/cupertino-sample-index-base-test")

    private var basePrefix: String {
        base.path.hasSuffix("/") ? base.path : base.path + "/"
    }

    @Test("Sample.Index.databasePath(baseDirectory:) sits under the supplied base")
    func samplesDatabaseUnderBase() {
        let path = Sample.Index.databasePath(baseDirectory: base)
        #expect(path.path.hasPrefix(basePrefix))
        // Post-#1037: the active filename is `apple-sample-code.db`. The
        // legacy `samples.db` filename is still reachable via
        // `Sample.Index.legacySamplesDatabasePath(baseDirectory:)` for
        // migration-detection codepaths.
        #expect(path.lastPathComponent == "apple-sample-code.db")
    }

    @Test("Sample.Index.legacySamplesDatabasePath(baseDirectory:) still resolves the pre-#1037 filename")
    func legacySamplesDatabaseUnderBase() {
        let path = Sample.Index.legacySamplesDatabasePath(baseDirectory: base)
        #expect(path.path.hasPrefix(basePrefix))
        #expect(path.lastPathComponent == "samples.db")
    }

    @Test("Sample.Index.sampleCodeDirectory(baseDirectory:) sits under the supplied base")
    func sampleCodeDirUnderBase() {
        let path = Sample.Index.sampleCodeDirectory(baseDirectory: base)
        #expect(path.path.hasPrefix(basePrefix))
        #expect(path.lastPathComponent == "sample-code")
    }
}
