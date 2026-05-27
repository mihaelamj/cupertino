import CorePackageIndexing
import CorePackageIndexingModels
import CoreProtocols
import CrawlerModels
import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - PackagesFetchStrategy

/// 2026-05-26 audit Finding 9.7 + 11.1: per-source fetch strategy
/// for `--source packages`. Wraps the 3-stage Swift Package Index
/// fetch + GitHub archive download + availability annotation
/// pipeline. Lifted from `CLIImpl.Command.Fetch.runPackageFetch` /
/// `runPackageMetadataStage` / `runPackageArchivesStage` /
/// `runPackageAnnotationStage`.
public struct PackagesFetchStrategy: Search.SourceFetchStrategy {
    public init() {}

    public func run(env: Search.FetchEnvironment) async throws {
        // #1108: stage 1 (SPI metadata + star-count refresh) is now
        // opt-in via `--refresh-metadata`; archives + annotation are
        // independent stages with their own opt-out / opt-in flags.
        // Reject the empty-pipeline combo with a diagnostic that
        // names the current CLI surface, not the removed
        // `--skip-metadata` flag.
        if !env.refreshMetadata, env.skipArchives, !env.annotateAvailability {
            env.logger.error(
                "❌ --skip-archives passed without --refresh-metadata or --annotate-availability. Nothing to do."
            )
            throw FetchError.nothingToDo
        }

        // GitHub token is only consulted by the stage-1 metadata
        // refresh (star-count sort hits api.github.com). The archive
        // download uses anonymous codeload.github.com, no token
        // needed. Only nag about the missing token when stage 1 is
        // actually about to run.
        if env.refreshMetadata,
           ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.githubToken] == nil {
            env.logger.info(Shared.Constants.Message.gitHubTokenTip)
            env.logger.info("   \(Shared.Constants.Message.rateLimitWithoutToken)")
            env.logger.info("   \(Shared.Constants.Message.rateLimitWithToken)")
            env.logger.info("   \(Shared.Constants.Message.exportGitHubToken)\n")
        }

        if env.refreshMetadata {
            try await runPackageMetadataStage(env: env)
        }

        if !env.skipArchives {
            try await runPackageArchivesStage(env: env)
        } else {
            env.logger.info("⏭  --skip-archives: skipping GitHub archive download")
        }

        if env.annotateAvailability {
            try await runPackageAnnotationStage(env: env)
        }
    }

    private func runPackageMetadataStage(env: Search.FetchEnvironment) async throws {
        env.logger.info("📇 Stage 1/2 — Refreshing Swift Package Index metadata")

        let fetcher = Core.PackageIndexing.PackageFetcher(
            outputDirectory: env.outputDirectory,
            limit: env.limit,
            resume: !env.startClean,
            logger: env.logger
        )

        let stats = try await fetcher.fetch(progress: PackageFetcherProgressObserver(recording: env.logger))

        env.logger.output("")
        env.logger.info("✅ Metadata refresh completed")
        env.logger.info("   Total packages: \(stats.totalPackages)")
        env.logger.info("   Successful: \(stats.successfulFetches)")
        env.logger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            env.logger.info("   Duration: \(Int(duration))s")
        }
        env.logger.info("   📁 \(env.outputDirectory.path)/\(Shared.Constants.FileName.packagesWithStars)\n")
    }

    // swiftlint:disable:next function_body_length
    private func runPackageArchivesStage(env: Search.FetchEnvironment) async throws {
        env.logger.info("📦 Stage 2/2 — Downloading priority package archives")

        // Path-DI: derive a Shared.Paths from the env's outputDirectory.
        // env.outputDirectory is `<base>/packages` by default; the
        // catalog needs the parent (the base directory itself).
        let baseDirectory = env.outputDirectory.deletingLastPathComponent()

        let priorityCatalog = Core.PackageIndexing.PriorityPackagesCatalog(baseDirectory: baseDirectory)
        let priorityPackages = await priorityCatalog.allPackages

        guard !priorityPackages.isEmpty else {
            let priorityPackagesPath = env.outputDirectory
                .appendingPathComponent(Shared.Constants.FileName.priorityPackages)
                .path
            env.logger.error("❌ Error: No priority packages found")
            env.logger.error("   Searched:")
            env.logger.error("   - \(priorityPackagesPath)")
            env.logger.error("   - Shared.Constants.CriticalApplePackages")
            env.logger.error("   - Shared.Constants.KnownEcosystemPackages")
            env.logger.error("\n   Please ensure at least one package source is configured.")
            throw FetchError.noPriorityPackages
        }

        let seedRefs = priorityPackages.compactMap { pkg -> Shared.Models.PackageReference? in
            let owner: String
            if let explicitOwner = pkg.owner, !explicitOwner.isEmpty {
                owner = explicitOwner
            } else {
                guard let url = URL(string: pkg.url) else { return nil }
                let pathComponents = Array(url.pathComponents.dropFirst())
                guard pathComponents.count >= 2 else { return nil }
                owner = pathComponents[0]
            }
            let isApple = owner == Shared.Constants.GitHubOrg.apple
                || owner == Shared.Constants.GitHubOrg.swiftlang
                || owner == Shared.Constants.GitHubOrg.swiftServer
            return Shared.Models.PackageReference(
                owner: owner,
                repo: pkg.repo,
                url: pkg.url,
                priority: isApple ? .appleOfficial : .ecosystem
            )
        }

        let exclusions = Core.PackageIndexing.ExclusionList.load(from: baseDirectory)
        let seedChecksum = Core.PackageIndexing.ResolvedPackagesStore.checksum(seeds: seedRefs, exclusions: exclusions)
        let resolvedStoreURL = baseDirectory
            .appendingPathComponent(Shared.Constants.FileName.resolvedPackages)
        let canonicalCacheURL = baseDirectory
            .appendingPathComponent(".cache")
            .appendingPathComponent(Shared.Constants.FileName.canonicalOwnersCache)

        let resolvedPackages: [Core.PackageIndexing.ResolvedPackage]
        if env.recurse {
            if !env.refresh,
               let cached = Core.PackageIndexing.ResolvedPackagesStore.load(from: resolvedStoreURL),
               cached.seedChecksum == seedChecksum {
                env.logger.info(
                    "🔗 Using cached closure from resolved-packages.json (\(cached.packages.count) packages, generated \(cached.generatedAt))"
                )
                resolvedPackages = cached.packages
            } else {
                if env.refresh {
                    env.logger.info("🔗 --refresh: discarding cached closure, re-walking dependency graphs...")
                } else {
                    env.logger.info("🔗 Resolving transitive dependencies for \(seedRefs.count) seed packages...")
                }
                if !exclusions.isEmpty {
                    env.logger.info("   Exclusion list in effect: \(exclusions.count) entries")
                }
                let canonicalizer = Core.PackageIndexing.GitHubCanonicalizer(cacheURL: canonicalCacheURL)
                let manifestCache = Core.PackageIndexing.ManifestCache(
                    rootDirectory: baseDirectory
                        .appendingPathComponent(".cache")
                        .appendingPathComponent("manifests")
                )
                let resolver = Core.PackageIndexing.PackageDependencyResolver(
                    canonicalizer: canonicalizer,
                    exclusions: exclusions,
                    manifestCache: manifestCache
                )
                let (resolved, resolverStats) = await resolver.resolve(
                    seeds: seedRefs,
                    progress: PackageDependencyResolverProgressObserver(recording: env.logger)
                )
                resolvedPackages = resolved
                env.logger.info("   Seeds: \(resolverStats.seedCount)")
                env.logger.info("   Discovered via dependencies: \(resolverStats.discoveredCount)")
                env.logger.info("   Excluded: \(resolverStats.excludedCount)")
                env.logger.info("   Skipped (non-GitHub): \(resolverStats.skippedNonGitHub)")
                env.logger.info("   Skipped (SPM registry id): \(resolverStats.skippedRegistry)")
                env.logger.info("   Missing manifest: \(resolverStats.missingManifest)")
                env.logger.info("   Malformed manifest: \(resolverStats.malformedManifest)")
                env.logger.info("   Resolver duration: \(Int(resolverStats.duration))s")

                let store = Core.PackageIndexing.ResolvedPackagesStore(
                    cupertinoVersion: Shared.Constants.App.version,
                    seedChecksum: seedChecksum,
                    packages: resolved
                )
                do {
                    try store.write(to: resolvedStoreURL)
                    env.logger.info("   Saved closure to \(resolvedStoreURL.path)")
                } catch {
                    env.logger.error("   ⚠️  Could not persist resolved-packages.json: \(error)")
                }
            }
        } else {
            resolvedPackages = seedRefs.map { ref in
                Core.PackageIndexing.ResolvedPackage(
                    owner: ref.owner,
                    repo: ref.repo,
                    url: ref.url,
                    priority: ref.priority,
                    parents: ["\(ref.owner.lowercased())/\(ref.repo.lowercased())"]
                )
            }
            env.logger.info("🔗 Skipping dependency resolution (--no-recurse)")
            if !exclusions.isEmpty {
                env.logger.info("   Exclusion list ignored while --no-recurse is set")
            }
        }

        env.logger.info("📦 Fetching \(resolvedPackages.count) archives into \(env.outputDirectory.path)...")

        let extractor = Core.PackageIndexing.PackageArchiveExtractor()
        let startedAt = Date()
        var stats = Shared.Models.PackageDownloadStatistics(
            totalPackages: resolvedPackages.count,
            startTime: startedAt
        )
        for (idx, pkg) in resolvedPackages.enumerated() {
            let label = "\(pkg.owner)/\(pkg.repo)"
            let pkgDir = env.outputDirectory
                .appendingPathComponent(pkg.owner)
                .appendingPathComponent(pkg.repo)
            do {
                let extraction = try await extractor.fetchAndExtract(
                    owner: pkg.owner,
                    repo: pkg.repo,
                    destination: pkgDir
                )
                try writePackageManifest(resolved: pkg, extraction: extraction, destination: pkgDir)
                stats.newPackages += 1
                stats.totalFilesSaved += extraction.files.count
                stats.totalBytesSaved += extraction.totalBytes
                let kb = extraction.totalBytes / 1024
                env.logger.info("  ✅ \(label) — \(extraction.files.count) files, \(kb) KB")
            } catch Core.PackageIndexing.PackageArchiveExtractor.ExtractError.tarballNotFound {
                stats.errors += 1
                env.logger.error("  ✗ \(label) — archive not found on any ref")
            } catch Core.PackageIndexing.PackageArchiveExtractor.ExtractError.tarballTooLarge(let bytes) {
                stats.errors += 1
                env.logger.error("  ✗ \(label) — archive too large (\(bytes / 1024 / 1024) MB)")
            } catch {
                stats.errors += 1
                env.logger.error("  ✗ \(label) — \(error.localizedDescription)")
            }

            if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 || idx + 1 == resolvedPackages.count {
                let percent = Double(idx + 1) / Double(resolvedPackages.count) * 100
                env.logger.output(
                    String(format: "📊 Progress: %.1f%% (%d/%d)", percent, idx + 1, resolvedPackages.count)
                )
            }
        }
        stats.endTime = Date()

        env.logger.output("")
        env.logger.info("✅ Archive download completed")
        env.logger.info("   New packages: \(stats.newPackages)")
        env.logger.info("   Files saved: \(stats.totalFilesSaved)")
        env.logger.info("   Bytes saved: \(stats.totalBytesSaved / 1024) KB")
        env.logger.info("   Errors: \(stats.errors)")
        if let duration = stats.duration {
            env.logger.info("   Duration: \(Int(duration))s")
        }
        env.logger.info("   📁 \(env.outputDirectory.path)")
        env.logger.info("   Next: index them via `cupertino save --source packages`")
    }

    private func runPackageAnnotationStage(env: Search.FetchEnvironment) async throws {
        env.logger.info("🏷  Stage 3 — Annotating availability metadata (#219)")

        let fm = FileManager.default
        guard fm.fileExists(atPath: env.outputDirectory.path) else {
            env.logger.error("❌ Packages directory \(env.outputDirectory.path) doesn't exist — run with stage 2 first.")
            throw FetchError.packagesDirectoryMissing
        }

        let owners = (try? Shared.Utils.FileSystem.contentsOfDirectory(at: env.outputDirectory, includingPropertiesForKeys: nil))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            ?? []

        let annotator = Core.PackageIndexing.PackageAvailabilityAnnotator()
        var packagesAnnotated = 0
        var totalAttrs = 0
        let startedAt = Date()

        for ownerURL in owners.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let repos = (try? Shared.Utils.FileSystem.contentsOfDirectory(at: ownerURL, includingPropertiesForKeys: nil))?
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                ?? []

            for repoURL in repos.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let label = "\(ownerURL.lastPathComponent)/\(repoURL.lastPathComponent)"
                do {
                    let result = try await annotator.annotate(packageDirectory: repoURL)
                    packagesAnnotated += 1
                    totalAttrs += result.stats.totalAttributes
                    env.logger.info(
                        "  ✅ \(label) — \(result.stats.totalAttributes) @available attrs across "
                            + "\(result.stats.filesWithAvailability)/\(result.stats.filesScanned) files"
                    )
                } catch {
                    env.logger.error("  ✗ \(label) — \(error.localizedDescription)")
                }
            }
        }

        let duration = Int(Date().timeIntervalSince(startedAt))
        env.logger.output("")
        env.logger.info("✅ Annotation completed")
        env.logger.info("   Packages annotated: \(packagesAnnotated)")
        env.logger.info("   Total @available attrs: \(totalAttrs)")
        env.logger.info("   Duration: \(duration)s")
    }

    private func writePackageManifest(
        resolved: Core.PackageIndexing.ResolvedPackage,
        extraction: Core.PackageIndexing.PackageExtractionResult,
        destination: URL
    ) throws {
        struct Manifest: Encodable {
            let owner: String
            let repo: String
            let url: String
            let fetchedAt: Date
            let cupertinoVersion: String
            let branch: String
            let parents: [String]
            let savedFileCount: Int
            let totalBytes: Int64
            let tarballBytes: Int
        }
        let manifest = Manifest(
            owner: resolved.owner,
            repo: resolved.repo,
            url: resolved.url,
            fetchedAt: Date(),
            cupertinoVersion: Shared.Constants.App.version,
            branch: extraction.branch,
            parents: resolved.parents,
            savedFileCount: extraction.files.count,
            totalBytes: extraction.totalBytes,
            tarballBytes: extraction.tarballBytes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: destination.appendingPathComponent("manifest.json"))
    }

    public enum FetchError: Error, CustomStringConvertible {
        case nothingToDo
        case noPriorityPackages
        case packagesDirectoryMissing
        public var description: String {
            switch self {
            case .nothingToDo: return "--skip-archives without --refresh-metadata or --annotate-availability: nothing to do"
            case .noPriorityPackages: return "No priority packages found"
            case .packagesDirectoryMissing: return "Packages directory missing — run stage 2 first"
            }
        }
    }
}

private struct PackageFetcherProgressObserver: Core.PackageIndexing.PackageFetcherProgressObserving {
    let recording: any LoggingModels.Logging.Recording

    func observe(progress: Core.PackageIndexing.PackageFetcherProgress) {
        let percent = String(format: "%.1f", progress.percentage)
        recording.output("   Progress: \(percent)% - \(progress.packageName)")
    }
}

private struct PackageDependencyResolverProgressObserver: Core.PackageIndexing.PackageDependencyResolverProgressObserving {
    let recording: any LoggingModels.Logging.Recording

    func observe(packageName: String, processed: Int, total: Int) {
        if processed == 1 || processed % 10 == 0 || processed == total {
            recording.output("   Resolving: \(processed)/\(total) (\(packageName))")
        }
    }
}
