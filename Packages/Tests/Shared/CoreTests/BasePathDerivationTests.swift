import Foundation
import SharedConstants
import Testing

/// Contract test for #535: every derived path on `Shared.Paths` must sit
/// under the supplied `baseDirectory`. Post-#535 the previous
/// `Shared.Constants.defaultX` static accessors (which routed through
/// `BinaryConfig.shared` — Service Locator) are deleted. The test
/// asserts the same wiring guarantee but against the explicit
/// `Shared.Paths(baseDirectory:)` value.
@Suite("Shared.Paths derives every subpath from its baseDirectory (#535)")
struct BasePathDerivationTests {
    private let base = URL(fileURLWithPath: "/tmp/cupertino-base-path-derivation-test")
    private var paths: Shared.Paths { Shared.Paths(baseDirectory: base) }

    private var basePrefix: String {
        // Trailing slash so "/foo" is not accepted as prefix of "/foobar".
        base.path.hasSuffix("/") ? base.path : base.path + "/"
    }

    private func assertUnderBase(_ url: URL, expectedLeaf: String) {
        #expect(url.path.hasPrefix(basePrefix), "\(url.path) is not under \(base.path)")
        #expect(url.lastPathComponent == expectedLeaf)
    }

    // MARK: - Subdirectories

    @Test("docsDirectory")
    func docs() {
        assertUnderBase(paths.docsDirectory, expectedLeaf: "docs")
    }

    @Test("swiftEvolutionDirectory")
    func swiftEvolution() {
        assertUnderBase(paths.swiftEvolutionDirectory, expectedLeaf: "swift-evolution")
    }

    @Test("swiftOrgDirectory")
    func swiftOrg() {
        assertUnderBase(paths.swiftOrgDirectory, expectedLeaf: "swift-org")
    }

    @Test("swiftBookDirectory")
    func swiftBook() {
        assertUnderBase(paths.swiftBookDirectory, expectedLeaf: "swift-book")
    }

    @Test("packagesDirectory")
    func packagesDir() {
        assertUnderBase(paths.packagesDirectory, expectedLeaf: "packages")
    }

    @Test("sampleCodeDirectory")
    func sampleCodeDir() {
        assertUnderBase(paths.sampleCodeDirectory, expectedLeaf: "sample-code")
    }

    @Test("archiveDirectory")
    func archive() {
        assertUnderBase(paths.archiveDirectory, expectedLeaf: "archive")
    }

    @Test("higDirectory")
    func hig() {
        assertUnderBase(paths.higDirectory, expectedLeaf: "hig")
    }

    // MARK: - Files

    @Test("metadataFile")
    func metadata() {
        assertUnderBase(paths.metadataFile, expectedLeaf: "metadata.json")
    }

    @Test("configFile")
    func configFile() {
        assertUnderBase(paths.configFile, expectedLeaf: "config.json")
    }

    @Test("searchDatabase")
    func searchDB() {
        assertUnderBase(paths.searchDatabase, expectedLeaf: "search.db")
    }

    @Test("packagesDatabase")
    func packagesDB() {
        assertUnderBase(paths.packagesDatabase, expectedLeaf: "packages.db")
    }

    // MARK: - Sanity

    @Test("baseDirectory round-trips through Shared.Paths init")
    func baseSanity() {
        #expect(paths.baseDirectory == base)
        #expect(base.isFileURL)
    }
}
