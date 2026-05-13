import Foundation
import SharedConstants
@testable import SharedCore
import Testing

/// Contract test for #211: every default path Cupertino exposes must derive
/// from `Shared.Constants.defaultBaseDirectory`. If a command starts hardcoding
/// `~/.cupertino` directly (or accessing `homeDirectoryForCurrentUser` itself),
/// the binary-co-located config override breaks for that command. These tests
/// assert the wiring stays intact.
@Suite("Default paths derive from defaultBaseDirectory (#211)")
struct BasePathDerivationTests {
    private let base = Shared.Constants.defaultBaseDirectory

    private var basePrefix: String {
        // Trailing slash so "/foo" is not accepted as prefix of "/foobar".
        base.path.hasSuffix("/") ? base.path : base.path + "/"
    }

    private func assertUnderBase(_ url: URL, expectedLeaf: String) {
        #expect(url.path.hasPrefix(basePrefix), "\(url.path) is not under \(base.path)")
        #expect(url.lastPathComponent == expectedLeaf)
    }

    // MARK: - Subdirectories

    @Test("defaultDocsDirectory")
    func docs() {
        assertUnderBase(Shared.Constants.defaultDocsDirectory, expectedLeaf: "docs")
    }

    @Test("defaultSwiftEvolutionDirectory")
    func swiftEvolution() {
        assertUnderBase(Shared.Constants.defaultSwiftEvolutionDirectory, expectedLeaf: "swift-evolution")
    }

    @Test("defaultSwiftOrgDirectory")
    func swiftOrg() {
        assertUnderBase(Shared.Constants.defaultSwiftOrgDirectory, expectedLeaf: "swift-org")
    }

    @Test("defaultSwiftBookDirectory")
    func swiftBook() {
        assertUnderBase(Shared.Constants.defaultSwiftBookDirectory, expectedLeaf: "swift-book")
    }

    @Test("defaultPackagesDirectory")
    func packagesDir() {
        assertUnderBase(Shared.Constants.defaultPackagesDirectory, expectedLeaf: "packages")
    }

    @Test("defaultSampleCodeDirectory")
    func sampleCodeDir() {
        assertUnderBase(Shared.Constants.defaultSampleCodeDirectory, expectedLeaf: "sample-code")
    }

    @Test("defaultArchiveDirectory")
    func archive() {
        assertUnderBase(Shared.Constants.defaultArchiveDirectory, expectedLeaf: "archive")
    }

    @Test("defaultHIGDirectory")
    func hig() {
        assertUnderBase(Shared.Constants.defaultHIGDirectory, expectedLeaf: "hig")
    }

    // MARK: - Files

    @Test("defaultMetadataFile")
    func metadata() {
        assertUnderBase(Shared.Constants.defaultMetadataFile, expectedLeaf: "metadata.json")
    }

    @Test("defaultConfigFile")
    func configFile() {
        assertUnderBase(Shared.Constants.defaultConfigFile, expectedLeaf: "config.json")
    }

    @Test("defaultSearchDatabase")
    func searchDB() {
        assertUnderBase(Shared.Constants.defaultSearchDatabase, expectedLeaf: "search.db")
    }

    @Test("defaultPackagesDatabase")
    func packagesDB() {
        assertUnderBase(Shared.Constants.defaultPackagesDatabase, expectedLeaf: "packages.db")
    }

    // MARK: - Sanity

    @Test("defaultBaseDirectory ends in the expected leaf or BinaryConfig override")
    func baseSanity() {
        // Either we hit the standard fallback (".cupertino") or BinaryConfig
        // returned a custom override URL. Both are valid; we just need a
        // non-empty path.
        #expect(!base.path.isEmpty)
        #expect(base.isFileURL)
    }
}
