import CorePackageIndexingModels
import CoreProtocols
import Foundation
import SharedConstants
import Testing

// Smoke tests for the CorePackageIndexingModels target. Pin the public
// surface so accidental renames or accidental cross-target imports fail
// fast in CI rather than at downstream-build time. Mirrors the
// SearchModelsTests / SampleIndexModelsTests pattern.

@Suite("CorePackageIndexingModels public surface")
struct CorePackageIndexingModelsTests {
    // MARK: - Namespace anchor

    @Test("Core.PackageIndexing namespace is reachable")
    func namespaceIsReachable() {
        // Compile-time check: writing the full path works. If the
        // anchor moves or the target stops re-exporting it, this stops
        // compiling.
        let _: Core.PackageIndexing.Type = Core.PackageIndexing.self
    }

    // MARK: - ResolvedPackage

    @Test("ResolvedPackage round-trips through JSON")
    func resolvedPackageRoundTrip() throws {
        let original = Core.PackageIndexing.ResolvedPackage(
            owner: "apple",
            repo: "swift-collections",
            url: "https://github.com/apple/swift-collections",
            priority: .appleOfficial,
            parents: ["apple/swift-collections"]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            Core.PackageIndexing.ResolvedPackage.self,
            from: encoded
        )

        #expect(decoded == original)
        #expect(decoded.priority == .appleOfficial)
        #expect(decoded.parents == ["apple/swift-collections"])
    }

    @Test("ResolvedPackage is Hashable for use in sets")
    func resolvedPackageIsHashable() {
        let a = Core.PackageIndexing.ResolvedPackage(
            owner: "a", repo: "x", url: "u",
            priority: .ecosystem, parents: []
        )
        let b = Core.PackageIndexing.ResolvedPackage(
            owner: "a", repo: "x", url: "u",
            priority: .ecosystem, parents: []
        )
        let c = Core.PackageIndexing.ResolvedPackage(
            owner: "z", repo: "x", url: "u",
            priority: .ecosystem, parents: []
        )
        #expect(Set([a, b, c]).count == 2)
    }

    // MARK: - PackageFileKind + ExtractedFile

    @Test("PackageFileKind has the expected case set")
    func packageFileKindCases() {
        let cases: Set<Core.PackageIndexing.PackageFileKind> = [
            .readme, .changelog, .license,
            .packageManifest, .packageResolved,
            .doccArticle, .doccTutorial,
            .source, .test, .example, .projectDoc,
        ]
        #expect(cases.count == 11)
    }

    @Test("PackageFileKindClassifier routes top-level files")
    func classifierTopLevel() {
        let readme = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "README.md")
        #expect(readme?.kind == .readme)

        let pkg = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Package.swift")
        #expect(pkg?.kind == .packageManifest)

        let unknown = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "weird.bin")
        #expect(unknown == nil)
    }

    @Test("PackageFileKindClassifier extracts module from Sources/")
    func classifierSourcesModule() {
        let result = Core.PackageIndexing.PackageFileKindClassifier.classify(
            relpath: "Sources/Logging/Logger.swift"
        )
        #expect(result?.kind == .source)
        #expect(result?.module == "Logging")
    }

    @Test("ExtractedFile holds the public fields")
    func extractedFileFields() {
        let file = Core.PackageIndexing.ExtractedFile(
            relpath: "Sources/Lib/X.swift",
            kind: .source,
            module: "Lib",
            content: "let x = 1\n",
            byteSize: 10
        )
        #expect(file.relpath == "Sources/Lib/X.swift")
        #expect(file.kind == .source)
        #expect(file.module == "Lib")
        #expect(file.byteSize == 10)
    }

    // MARK: - PackageExtractionResult

    @Test("PackageExtractionResult holds branch + files + sizes")
    func packageExtractionResultFields() {
        let result = Core.PackageIndexing.PackageExtractionResult(
            branch: "main",
            files: [],
            totalBytes: 12345,
            tarballBytes: 6789
        )
        #expect(result.branch == "main")
        #expect(result.totalBytes == 12345)
        #expect(result.tarballBytes == 6789)
        #expect(result.files.isEmpty)
    }

    // MARK: - availabilityFilename

    @Test("availabilityFilename constant matches the legacy sidecar name")
    func availabilityFilenameConstant() {
        #expect(Core.PackageIndexing.availabilityFilename == "availability.json")
    }
}
