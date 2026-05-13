import Foundation
@testable import SampleIndex
import SharedConstants
import SharedCore
import Testing

/// Companion to `BasePathDerivationTests` in SharedTests, covering the
/// SampleIndex-side defaults. Asserts that the samples database path and the
/// sample-code directory both sit under `Shared.Constants.defaultBaseDirectory`,
/// so the binary-co-located config (#211) redirects them uniformly.
@Suite("SampleIndex default paths derive from defaultBaseDirectory (#211)")
struct SampleIndexBasePathDerivationTests {
    private let base = Shared.Constants.defaultBaseDirectory

    private var basePrefix: String {
        base.path.hasSuffix("/") ? base.path : base.path + "/"
    }

    @Test("Sample.Index.defaultDatabasePath sits under defaultBaseDirectory")
    func samplesDatabaseUnderBase() {
        let path = Sample.Index.defaultDatabasePath
        #expect(path.path.hasPrefix(basePrefix))
        #expect(path.lastPathComponent == "samples.db")
    }

    @Test("Sample.Index.defaultSampleCodeDirectory sits under defaultBaseDirectory")
    func sampleCodeDirUnderBase() {
        let path = Sample.Index.defaultSampleCodeDirectory
        #expect(path.path.hasPrefix(basePrefix))
        #expect(path.lastPathComponent == "sample-code")
    }
}
