import Core
import Foundation
import Shared

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

        public enum IndexerError: Error, LocalizedError {
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
            rootDirectory: URL = Shared.Constants.defaultPackagesDirectory,
            index: PackageIndex
        ) {
            self.rootDirectory = rootDirectory
            self.index = index
        }

        /// Walk `<root>/<owner>/<repo>/` for each package, read its manifest +
        /// files, and index it. Missing or malformed manifests are logged and
        /// skipped without aborting the whole run.
        public func indexAll(
            onProgress: (@Sendable (String, Int, Int) -> Void)? = nil
        ) async throws -> Statistics {
            let startedAt = Date()
            var stats = Statistics()

            let packageDirs = try discoverPackageDirectories()
            guard !packageDirs.isEmpty else {
                throw IndexerError.noPackagesFound(rootDirectory)
            }

            for (idx, dir) in packageDirs.enumerated() {
                let label = "\(dir.deletingLastPathComponent().lastPathComponent)/\(dir.lastPathComponent)"
                onProgress?(label, idx + 1, packageDirs.count)
                do {
                    let (resolved, files, tarballBytes) = try loadPackage(at: dir)
                    let result = Core.PackageArchiveExtractor.Result(
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
            let ownerURLs = try FileManager.default.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for ownerURL in ownerURLs {
                let isDir = (try? ownerURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                let repoURLs = (try? FileManager.default.contentsOfDirectory(
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
            let resolvedPackage: Core.ResolvedPackage
            let branchFromManifest: String?
        }

        private func loadPackage(at dir: URL) throws -> (LoadedPackage, [Core.ExtractedFile], Int?) {
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

            let priority: PackagePriority
            if manifest.owner == Shared.Constants.GitHubOrg.apple
                || manifest.owner == Shared.Constants.GitHubOrg.swiftlang
                || manifest.owner == Shared.Constants.GitHubOrg.swiftServer {
                priority = .appleOfficial
            } else {
                priority = .ecosystem
            }

            let resolved = Core.ResolvedPackage(
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
        nonisolated static func loadAvailability(at dir: URL) -> PackageIndex.AvailabilityPayload? {
            let url = dir.appendingPathComponent(Core.PackageAvailabilityAnnotator.outputFilename)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let result = try? decoder.decode(
                Core.PackageAvailabilityAnnotator.AnnotationResult.self,
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
            return PackageIndex.AvailabilityPayload(
                deploymentTargets: result.deploymentTargets,
                attributesByRelpath: attrsByRelpath,
                source: "package-swift"
            )
        }

        private nonisolated func walkDirectoryForFiles(dir: URL) -> [Core.ExtractedFile] {
            var files: [Core.ExtractedFile] = []
            let rootComponents = dir.resolvingSymlinksInPath().pathComponents

            guard let enumerator = FileManager.default.enumerator(
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
                    || name == Core.PackageAvailabilityAnnotator.outputFilename {
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

                guard let classified = Core.PackageFileKindClassifier.classify(relpath: relpath) else { continue }
                guard let content = try? String(contentsOf: candidate, encoding: .utf8) else { continue }

                files.append(Core.ExtractedFile(
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
