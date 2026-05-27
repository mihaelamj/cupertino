import ASTIndexer
import CorePackageIndexingModels
import CoreProtocols
import Foundation
import SampleIndexModels
import SearchModels
import SharedConstants

extension Search {
    /// Reads downloaded-and-extracted package trees from
    /// `~/.cupertino/packages/<owner>/<repo>/` and feeds them into the
    /// `PackageIndex`. Keeps fetch and index as separate concerns so any
    /// failure in one doesn't force a redo of the other — the same pattern
    /// cupertino follows for Apple docs, Swift Evolution, and samples.
    public actor PackageIndexer {
        public struct Statistics: Sendable {
            public var packagesIndexed: Int = 0
            public var packagesFailed: Int = 0
            public var totalFiles: Int = 0
            public var totalBytes: Int64 = 0
            public var durationSeconds: TimeInterval = 0
        }

        public enum IndexerError: Swift.Error, LocalizedError {
            case noPackagesFound(URL)
            case manifestMissing(URL)
            case manifestMalformed(URL, String)

            public var errorDescription: String? {
                switch self {
                case .noPackagesFound(let url): return "No package trees found under \(url.path)"
                case .manifestMissing(let url): return "manifest.json missing at \(url.path)"
                case .manifestMalformed(let url, let reason): return "manifest.json malformed at \(url.path): \(reason)"
                }
            }
        }

        private let rootDirectory: URL
        private let index: PackageIndex

        public init(
            rootDirectory: URL,
            index: PackageIndex
        ) {
            self.rootDirectory = rootDirectory
            self.index = index
        }

        /// Walk `<root>/<owner>/<repo>/` for each package, read its manifest +
        /// files, and index it. Missing or malformed manifests are logged and
        /// skipped without aborting the whole run.
        ///
        /// - Parameter progress: Optional GoF Observer
        ///   (`Search.PackageIndexingProgressReporting`) called per package
        ///   with the package label and the running `(processed, total)`
        ///   count. Pass `nil` to opt out of progress reports. Replaces the
        ///   previous `onProgress: @Sendable (String, Int, Int) -> Void`
        ///   closure parameter per the standing "no closures, they ate
        ///   magic" rule.
        public func indexAll(
            progress: (any Search.PackageIndexingProgressReporting)? = nil
        ) async throws -> Statistics {
            let startedAt = Date()
            var stats = Statistics()

            let packageDirs = try discoverPackageDirectories()
            guard !packageDirs.isEmpty else {
                throw IndexerError.noPackagesFound(rootDirectory)
            }

            for (idx, dir) in packageDirs.enumerated() {
                let label = "\(dir.deletingLastPathComponent().lastPathComponent)/\(dir.lastPathComponent)"
                progress?.report(packageName: label, processed: idx + 1, total: packageDirs.count)
                do {
                    let (resolved, files, tarballBytes) = try loadPackage(at: dir)
                    let result = Core.PackageIndexing.PackageExtractionResult(
                        branch: resolved.branchFromManifest ?? "HEAD",
                        files: files,
                        totalBytes: files.reduce(Int64(0)) { $0 + Int64($1.byteSize) },
                        tarballBytes: tarballBytes ?? 0
                    )
                    let availability = Self.loadAvailability(at: dir)
                    let outcome = try await index.index(
                        resolved: resolved.resolvedPackage,
                        extraction: result,
                        availability: availability
                    )
                    stats.packagesIndexed += 1
                    stats.totalFiles += outcome.filesIndexed
                    stats.totalBytes += outcome.bytesIndexed
                } catch {
                    stats.packagesFailed += 1
                }
            }

            stats.durationSeconds = Date().timeIntervalSince(startedAt)
            return stats
        }

        // MARK: - Disk walk

        private func discoverPackageDirectories() throws -> [URL] {
            guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
                return []
            }
            var result: [URL] = []
            let ownerURLs = try Shared.Utils.FileSystem.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for ownerURL in ownerURLs {
                let isDir = (try? ownerURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                let repoURLs = (try? Shared.Utils.FileSystem.contentsOfDirectory(
                    at: ownerURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for repoURL in repoURLs {
                    let isRepoDir = (try? repoURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    guard isRepoDir else { continue }
                    result.append(repoURL)
                }
            }
            return result.sorted { $0.path < $1.path }
        }

        private struct ManifestShape: Decodable {
            let owner: String
            let repo: String
            let url: String
            let branch: String?
            let parents: [String]?
            let tarballBytes: Int?
        }

        private struct LoadedPackage {
            let resolvedPackage: Core.PackageIndexing.ResolvedPackage
            let branchFromManifest: String?
        }

        private func loadPackage(at dir: URL) throws -> (LoadedPackage, [Core.PackageIndexing.ExtractedFile], Int?) {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                throw IndexerError.manifestMissing(manifestURL)
            }
            let data = try Data(contentsOf: manifestURL)
            let manifest: ManifestShape
            do {
                manifest = try JSONDecoder().decode(ManifestShape.self, from: data)
            } catch {
                throw IndexerError.manifestMalformed(manifestURL, String(describing: error))
            }

            let priority: Shared.Models.PackagePriority
            if manifest.owner == Shared.Constants.GitHubOrg.apple
                || manifest.owner == Shared.Constants.GitHubOrg.swiftlang
                || manifest.owner == Shared.Constants.GitHubOrg.swiftServer {
                priority = .appleOfficial
            } else {
                priority = .ecosystem
            }

            let resolved = Core.PackageIndexing.ResolvedPackage(
                owner: manifest.owner,
                repo: manifest.repo,
                url: manifest.url,
                priority: priority,
                parents: manifest.parents ?? ["\(manifest.owner.lowercased())/\(manifest.repo.lowercased())"]
            )

            let files = walkDirectoryForFiles(dir: dir)
            return (
                LoadedPackage(resolvedPackage: resolved, branchFromManifest: manifest.branch),
                files,
                manifest.tarballBytes
            )
        }

        /// Load `<dir>/availability.json` if present and decode it into the
        /// `PackageIndex.AvailabilityPayload` shape #219 stage 3 produces.
        /// Returns nil when the file is missing or unparseable so callers
        /// pass `availability: nil` and the new columns stay NULL — caller
        /// can still distinguish "not annotated" from "annotated but empty".
        ///
        /// #861 fallback: an older `PackageAvailabilityAnnotator` shipped
        /// before #225 Part A and wrote `availability.json` files
        /// WITHOUT the `swiftToolsVersion` field. Brew-shipped package
        /// corpora that were annotated by that older annotator therefore
        /// decode here with `result.swiftToolsVersion == nil` even
        /// though `<dir>/Package.swift` line 1 carries a valid
        /// `// swift-tools-version: X.Y` declaration. Caused 0/183
        /// coverage on the dev corpus pre-fix. The fallback below reads
        /// `<dir>/Package.swift` directly and parses line 1 via the
        /// shared `ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion`
        /// path — same parser the annotator uses — so coverage tracks
        /// what's actually on disk, not what the (possibly-stale)
        /// availability.json captured.
        nonisolated static func loadAvailability(at dir: URL) -> PackageIndex.AvailabilityPayload? {
            let url = dir.appendingPathComponent(Core.PackageIndexing.availabilityFilename)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let result = try? decoder.decode(
                Core.PackageIndexing.AnnotationResult.self,
                from: data
            ) else { return nil }

            var attrsByRelpath: [String: [PackageIndex.AvailabilityPayload.FileAttribute]] = [:]
            for fileAvail in result.fileAvailability {
                attrsByRelpath[fileAvail.relpath] = fileAvail.attributes.map {
                    PackageIndex.AvailabilityPayload.FileAttribute(
                        line: $0.line,
                        raw: $0.raw,
                        platforms: $0.platforms
                    )
                }
            }

            // #861 — fall back to a direct Package.swift line-1 read
            // when the decoded JSON lacks the field (pre-#225-Part-A
            // annotator shape). Same parser as the annotator's own
            // call site so both paths converge on the same value.
            let swiftToolsVersion: String? = result.swiftToolsVersion
                ?? readSwiftToolsVersionFromPackageManifest(at: dir)

            // #1114: MAX-merge per-file @available aggregation with
            // Package.swift deployment targets. Parallel to #1111
            // for apple-sample-code. The per-file attributes are
            // already on disk in availability.json; pre-#1114 they
            // were only persisted per-file (attrsByRelpath) but
            // never aggregated into the project-level
            // package_metadata.min_<platform> columns. A package
            // that uses `@available(iOS 17.0, *)` APIs in its
            // sources unconditionally needs iOS 17 to compile;
            // pre-#1114 the row stamped iOS 13 from
            // Package.swift platforms only.
            let astAttrs = result.fileAvailability.flatMap { fileAvail in
                fileAvail.attributes.map {
                    ASTIndexer.AvailabilityParsers.Attribute(
                        line: $0.line, raw: $0.raw, platforms: $0.platforms
                    )
                }
            }
            let aggregated = SampleAvailableAttributeAggregator.aggregate(attributes: astAttrs)
            let packageSwift = Self.platformVersionsFromDict(result.deploymentTargets)
            let merged = Self.maxMergePlatformVersions(aggregated, packageSwift)
            let mergedDict: [String: String]
            if let merged {
                mergedDict = Self.dictFromPlatformVersions(merged.versions)
            } else {
                mergedDict = result.deploymentTargets
            }
            let source: String
            if let merged, merged.aggregatedContributed {
                source = "package-available-aggregated"
            } else {
                source = "package-swift"
            }

            return PackageIndex.AvailabilityPayload(
                deploymentTargets: mergedDict,
                attributesByRelpath: attrsByRelpath,
                source: source,
                // #225 Part A — propagate the swift-tools-version from the
                // annotator's read of Package.swift line 1. Nil when the
                // manifest didn't carry a declaration we could parse AND
                // the fallback read of Package.swift also turned up empty.
                swiftToolsVersion: swiftToolsVersion
            )
        }

        // MARK: - #1114 MAX-merge helpers

        /// Build a `Search.PlatformVersions` from the dict shape
        /// `availability.json.deploymentTargets` uses (keys
        /// `"iOS"`/`"macOS"`/etc., values version strings).
        nonisolated static func platformVersionsFromDict(_ dict: [String: String]) -> Search.PlatformVersions? {
            if dict.isEmpty { return nil }
            return Search.PlatformVersions(
                iOS: dict["iOS"],
                macOS: dict["macOS"],
                tvOS: dict["tvOS"],
                watchOS: dict["watchOS"],
                visionOS: dict["visionOS"]
            )
        }

        /// Inverse of `platformVersionsFromDict` — drop nil
        /// platforms so the resulting dict's keys are present
        /// only when the platform has a value.
        nonisolated static func dictFromPlatformVersions(_ versions: Search.PlatformVersions) -> [String: String] {
            var dict: [String: String] = [:]
            if let value = versions.iOS { dict["iOS"] = value }
            if let value = versions.macOS { dict["macOS"] = value }
            if let value = versions.tvOS { dict["tvOS"] = value }
            if let value = versions.watchOS { dict["watchOS"] = value }
            if let value = versions.visionOS { dict["visionOS"] = value }
            return dict
        }

        /// Per-platform MAX-merge of (aggregator-derived, Package.swift-
        /// derived) `Search.PlatformVersions`. Mirrors the
        /// `Sample.Index.Builder.maxMergePlatformVersions` shape from
        /// #1111 critic-pass. Reports whether the aggregator's value
        /// won any platform's MAX — the deciding bit for the
        /// `package-available-aggregated` vs `package-swift` tag.
        nonisolated static func maxMergePlatformVersions(
            _ aggregated: Search.PlatformVersions?,
            _ packageSwift: Search.PlatformVersions?
        ) -> (versions: Search.PlatformVersions, aggregatedContributed: Bool)? {
            if aggregated == nil, packageSwift == nil { return nil }
            var aggregatedContributed = false
            func merge(_ aggregatedValue: String?, _ packageSwiftValue: String?) -> String? {
                switch (aggregatedValue, packageSwiftValue) {
                case (nil, nil): return nil
                case let (.some(value), nil):
                    aggregatedContributed = true
                    return value
                case let (nil, .some(value)):
                    return value
                case let (.some(aggValue), .some(pkgValue)):
                    if Self.compareDottedVersions(aggValue, pkgValue) >= 0 {
                        if aggValue != pkgValue { aggregatedContributed = true }
                        return aggValue
                    }
                    return pkgValue
                }
            }
            let versions = Search.PlatformVersions(
                iOS: merge(aggregated?.iOS, packageSwift?.iOS),
                macOS: merge(aggregated?.macOS, packageSwift?.macOS),
                tvOS: merge(aggregated?.tvOS, packageSwift?.tvOS),
                watchOS: merge(aggregated?.watchOS, packageSwift?.watchOS),
                visionOS: merge(aggregated?.visionOS, packageSwift?.visionOS)
            )
            if versions.iOS == nil, versions.macOS == nil, versions.tvOS == nil,
               versions.watchOS == nil, versions.visionOS == nil {
                return nil
            }
            return (versions, aggregatedContributed)
        }

        /// Compare two dotted-int version strings: returns negative,
        /// zero, or positive in the same shape as `String.compare`.
        /// Missing components treated as 0 (so `"14"` == `"14.0"`).
        nonisolated static func compareDottedVersions(_ lhs: String, _ rhs: String) -> Int {
            let lhsParts = lhs.split(separator: ".").compactMap { Int($0) }
            let rhsParts = rhs.split(separator: ".").compactMap { Int($0) }
            let count = max(lhsParts.count, rhsParts.count)
            for idx in 0..<count {
                let left = idx < lhsParts.count ? lhsParts[idx] : 0
                let right = idx < rhsParts.count ? rhsParts[idx] : 0
                if left != right { return left - right }
            }
            return 0
        }

        /// #861 fallback helper. Read `<dir>/Package.swift` if present
        /// and run the shared `// swift-tools-version: X.Y` parser
        /// over it. Returns nil when the file is missing, unreadable,
        /// or carries no recognisable declaration.
        nonisolated static func readSwiftToolsVersionFromPackageManifest(at dir: URL) -> String? {
            let url = dir.appendingPathComponent("Package.swift")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let manifest = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: manifest)
        }

        private nonisolated func walkDirectoryForFiles(dir: URL) -> [Core.PackageIndexing.ExtractedFile] {
            var files: [Core.PackageIndexing.ExtractedFile] = []
            let rootComponents = dir.resolvingSymlinksInPath().pathComponents

            guard let enumerator = Shared.Utils.FileSystem.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
            ) else {
                return files
            }

            while let candidate = enumerator.nextObject() as? URL {
                let name = candidate.lastPathComponent
                // Skip the retained tarball, the manifest, and the
                // sidecar availability annotation file (#219) — none are
                // user-authored content.
                if name == ".archive.tar.gz"
                    || name == "manifest.json"
                    || name == Core.PackageIndexing.availabilityFilename {
                    continue
                }

                guard
                    let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                    values.isRegularFile == true,
                    let size = values.fileSize
                else { continue }

                let candidateComponents = candidate.resolvingSymlinksInPath().pathComponents
                guard candidateComponents.count > rootComponents.count else { continue }
                let relpath = candidateComponents
                    .dropFirst(rootComponents.count)
                    .joined(separator: "/")

                guard let classified = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: relpath) else { continue }
                guard let content = try? String(contentsOf: candidate, encoding: .utf8) else { continue }

                files.append(Core.PackageIndexing.ExtractedFile(
                    relpath: relpath,
                    kind: classified.kind,
                    module: classified.module,
                    content: content,
                    byteSize: size
                ))
            }
            return files
        }
    }
}
