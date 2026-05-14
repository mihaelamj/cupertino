@testable import CorePackageIndexing
import CoreProtocols
import Foundation
import Testing

// MARK: - CorePackageIndexing Public API Smoke Tests

// Core.PackageIndexing owns the Swift Packages pipeline that drives the
// packages.db catalog: manifest parsing, archive extraction, dependency
// resolution, file kind classification, availability annotation, and the
// priority-packages catalog compiled in at build time.
//
// Per #393 independence acceptance: CorePackageIndexing imports only
// Foundation + ASTIndexer + CoreProtocols + Logging + Resources +
// SharedConstants + SharedCore + SharedModels + SharedUtils. All eight
// internal deps are themselves DI-leaf-pinned (#382, #383, #384, #385,
// #386, #387, #388, #391). The package is structurally independent.
//
// Drive-by from this PR: the source imports `Resources` directly but
// the target's `dependencies` array previously didn't list it
// (Resources was reaching the target transitively via CoreProtocols).
// Resources is now an explicit dep so the declared deps match the
// observed imports.
//
// Behavioural tests for the full package-indexing pipeline (archive
// extract + manifest + dep resolution + availability annotation) live
// downstream where filesystem fixtures + real package zips can be wired
// up. This suite proves the public surface compiles and the canonical
// types stay reachable from a consumer that imports nothing but
// CorePackageIndexing.

@Suite("CorePackageIndexing public surface")
struct CorePackageIndexingPublicSurfaceTests {
    // MARK: Namespace

    @Test("Core.PackageIndexing namespace reachable")
    func packageIndexingNamespace() {
        _ = Core.PackageIndexing.self
    }

    // MARK: PackageFileKind raw values

    @Test("Core.PackageIndexing.PackageFileKind raw values are stable")
    func packageFileKindRawValues() {
        // The String raw values back the on-disk `kind` column in the
        // packages.db file-kind index. Renaming silently invalidates
        // every classified file. Pin all 11.
        let mapping: [Core.PackageIndexing.PackageFileKind: String] = [
            .readme: "readme",
            .changelog: "changelog",
            .license: "license",
            .packageManifest: "packageManifest",
            .packageResolved: "packageResolved",
            .doccArticle: "doccArticle",
            .doccTutorial: "doccTutorial",
            .source: "source",
            .test: "test",
            .example: "example",
            .projectDoc: "projectDoc",
        ]
        for (kind, raw) in mapping {
            #expect(kind.rawValue == raw)
        }
    }

    // MARK: PackageFileKindClassifier — pure-input classification

    @Test("PackageFileKindClassifier identifies a README at the package root")
    func classifierReadme() {
        let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "README.md")
        #expect(result?.kind == .readme)
    }

    @Test("PackageFileKindClassifier identifies Package.swift as packageManifest")
    func classifierPackageManifest() {
        let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Package.swift")
        #expect(result?.kind == .packageManifest)
    }

    @Test("PackageFileKindClassifier identifies Sources/Foo/Foo.swift as source with module Foo")
    func classifierSourceModule() {
        let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Sources/Foo/Foo.swift")
        #expect(result?.kind == .source)
        #expect(result?.module == "Foo")
    }

    @Test("PackageFileKindClassifier identifies Tests/FooTests/FooTests.swift as test")
    func classifierTest() {
        let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Tests/FooTests/FooTests.swift")
        #expect(result?.kind == .test)
    }

    // MARK: ResolvedPackagesStore schema version

    @Test("ResolvedPackagesStore.currentSchemaVersion is pinned at 1")
    func resolvedPackagesStoreSchemaVersion() {
        // Bumping triggers a packages.db rebuild; pin so accidental
        // bumps land deliberately.
        #expect(Core.PackageIndexing.ResolvedPackagesStore.currentSchemaVersion == 1)
    }

    // MARK: PriorityPackagesCatalog — compiled-in metadata

    @Test("PriorityPackagesCatalog exposes non-empty version / lastUpdated / description")
    func priorityPackagesCatalogMetadata() async {
        // Post-#535: PriorityPackagesCatalog is an actor constructed with
        // a baseDirectory. Use a temp dir + bundled-only so the test
        // doesn't touch real ~/.cupertino state.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("priority-catalog-metadata-\(UUID().uuidString)")
        let catalog = Core.PackageIndexing.PriorityPackagesCatalog(
            baseDirectory: tempDir,
            useBundledOnly: true
        )
        let version = await catalog.version
        let lastUpdated = await catalog.lastUpdated
        let description = await catalog.description
        #expect(!version.isEmpty)
        #expect(!lastUpdated.isEmpty)
        #expect(!description.isEmpty)
    }

    @Test("PriorityPackagesCatalog allPackages = applePackages + ecosystemPackages")
    func priorityPackagesCatalogAllPackagesPartition() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("priority-catalog-partition-\(UUID().uuidString)")
        let catalog = Core.PackageIndexing.PriorityPackagesCatalog(
            baseDirectory: tempDir,
            useBundledOnly: true
        )
        let apple = await catalog.applePackages
        let ecosystem = await catalog.ecosystemPackages
        let all = await catalog.allPackages
        // The partition contract: every package in `allPackages` comes
        // from either the apple or ecosystem buckets. Pin it so a
        // refactor that adds a third bucket doesn't silently leave
        // allPackages behind.
        #expect(all.count == apple.count + ecosystem.count)
    }

    @Test("PriorityPackagesCatalog stats + tiers reachable")
    func priorityPackagesCatalogStatsReachable() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("priority-catalog-stats-\(UUID().uuidString)")
        let catalog = Core.PackageIndexing.PriorityPackagesCatalog(
            baseDirectory: tempDir,
            useBundledOnly: true
        )
        let stats = await catalog.stats
        let tiers = await catalog.tiers
        // Don't pin the exact stat field name; just verify both async
        // accessors compile + return a value (the value types are part
        // of the public surface).
        _ = stats
        _ = tiers
    }

    // MARK: Public actor types are reachable

    @Test("Core.PackageIndexing actors and structs are reachable")
    func publicTypesReachable() {
        _ = Core.PackageIndexing.ManifestCache.self
        _ = Core.PackageIndexing.PackageArchiveExtractor.self
        _ = Core.PackageIndexing.PackageDocumentationDownloader.self
        _ = Core.PackageIndexing.PackageDependencyResolver.self
        _ = Core.PackageIndexing.PackageFetcher.self
        _ = Core.PackageIndexing.PackageAvailabilityAnnotator.self
        _ = Core.PackageIndexing.PackageFetcher.PackageInfo.self
        _ = Core.PackageIndexing.PackageFetcher.FetchOutput.self
        _ = Core.PackageIndexing.PackageFetcher.Checkpoint.self
    }
}
