import CoreProtocols
import Foundation

// MARK: - Core.PackageIndexing Namespace

extension Core {
    /// Sub-namespace for Swift Package indexing: catalog generation, archive
    /// extraction, manifest caching, dependency resolution, availability
    /// annotation, and the priority-package generator that drives the
    /// embedded catalog. Mirrors the `Sources/Core/PackageIndexing/` folder
    /// on disk.
    ///
    /// Layout:
    /// - `Core.PackageIndexing.ManifestCache` — cached Package.swift parses.
    /// - `Core.PackageIndexing.PackageArchiveExtractor` — zip → on-disk.
    /// - `Core.PackageIndexing.PackageAvailabilityAnnotator` — sweep platforms.
    /// - `Core.PackageIndexing.PackageDependencyResolver` — resolves Package.resolved.
    /// - `Core.PackageIndexing.PackageFileKind` — markdown / source / etc.
    /// - `Core.PackageIndexing.ResolvedPackagesStore` — on-disk cache.
    /// - `Core.PackageIndexing.PackageDocumentationDownloader` — README + hosted-docs fetch.
    /// - `Core.PackageIndexing.PackageFetcher` + `PackageInfo`,
    ///   `PackageFetchOutput`, `PackageFetchCheckpoint`,
    ///   `PackageFetchStatistics`, `PackageFetchProgress`.
    /// - `Core.PackageIndexing.PriorityPackageGenerator` + `PriorityPackageList`,
    ///   `PriorityLevels`, `TierInfo`, `PriorityPackageInfo`, `PackageStats`,
    ///   `PriorityPackageGenerator.Error`.
    /// - `Core.PackageIndexing.PriorityPackagesCatalog` + `PriorityPackage`,
    ///   `PriorityTier`, `PriorityTiers`, `PriorityPackageStats`.
    public enum PackageIndexing {}
}
