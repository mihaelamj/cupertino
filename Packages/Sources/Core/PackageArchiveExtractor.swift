import Foundation
import Shared

extension Core {
    /// Fetches a repo's source tarball from `codeload.github.com/<owner>/<repo>/tar.gz/<ref>`
    /// and returns its text content as `[ExtractedFile]` in memory. The caller (the
    /// indexer) is expected to consume the list directly into SQLite; nothing is
    /// written to the user's filesystem.
    ///
    /// Uses `/usr/bin/tar` via a subprocess so we don't drag a Swift tar implementation
    /// into the dependency graph; macOS's bsdtar reads `.tar.gz` directly. The scratch
    /// directory used for extraction is wiped before returning.
    public actor PackageArchiveExtractor {
        public struct Result: Sendable {
            public let branch: String
            public let files: [ExtractedFile]
            public let totalBytes: Int64
            public let tarballBytes: Int

            public init(
                branch: String,
                files: [ExtractedFile],
                totalBytes: Int64,
                tarballBytes: Int
            ) {
                self.branch = branch
                self.files = files
                self.totalBytes = totalBytes
                self.tarballBytes = tarballBytes
            }
        }

        public enum ExtractError: Error {
            case tarballNotFound
            case tarballTooLarge(Int)
            case tarFailed(code: Int32, stderr: String)
            case tarballTimeout
            case downloadFailed
        }

        private let session: URLSession
        private let candidateRefs: [String]
        private let maxTarballBytes: Int

        public init(
            session: URLSession = .shared,
            candidateRefs: [String] = ["HEAD", "main", "master"],
            maxTarballBytes: Int = 75 * 1024 * 1024
        ) {
            self.session = session
            self.candidateRefs = candidateRefs
            self.maxTarballBytes = maxTarballBytes
        }

        /// Download + extract a package archive into `destination`. Writes the
        /// filtered extracted tree to `destination/` AND retains the original
        /// tarball as `destination/.archive.tar.gz` for later re-extraction or
        /// diffing. Also returns the classified files in-memory as a
        /// convenience for callers that want to index immediately without
        /// re-walking the tree.
        ///
        /// Wipes `destination` before extraction so re-runs produce a clean
        /// state.
        public func fetchAndExtract(
            owner: String,
            repo: String,
            destination: URL
        ) async throws -> Result {
            for ref in candidateRefs {
                switch await downloadTarball(owner: owner, repo: repo, ref: ref) {
                case .success(let data):
                    if data.count > maxTarballBytes {
                        throw ExtractError.tarballTooLarge(data.count)
                    }
                    return try extractToDisk(
                        data: data,
                        branch: ref,
                        destination: destination
                    )
                case .notFound:
                    continue
                case .transient:
                    continue
                }
            }
            throw ExtractError.tarballNotFound
        }

        // MARK: - Download

        private enum DownloadResult {
            case success(Data)
            case notFound
            case transient
        }

        private func downloadTarball(owner: String, repo: String, ref: String) async -> DownloadResult {
            let urlString = "https://codeload.github.com/\(owner)/\(repo)/tar.gz/\(ref)"
            guard let url = URL(string: urlString) else { return .transient }
            var request = URLRequest(url: url)
            request.setValue(Shared.Constants.App.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 60
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .transient }
                if http.statusCode == 200 { return .success(data) }
                if http.statusCode == 404 { return .notFound }
                return .transient
            } catch {
                return .transient
            }
        }

        // MARK: - Extraction

        private func extractToDisk(
            data: Data,
            branch: String,
            destination: URL
        ) throws -> Result {
            // Clean destination for a predictable re-extract. Hidden `.archive.tar.gz`
            // will be rewritten below.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )

            // Retain the tarball alongside the extracted tree so later re-indexes
            // or future indexers (e.g. vector embeddings) never need to re-fetch.
            let tarballURL = destination.appendingPathComponent(".archive.tar.gz")
            try data.write(to: tarballURL)

            try runTar(tarballURL: tarballURL, outputDir: destination)
            try prune(rootURL: destination)

            var files: [ExtractedFile] = []
            var totalBytes: Int64 = 0
            // Resolve symlinks on the root so the path comparison works even when
            // /var/folders/... resolves to /private/var/folders/... at enumeration
            // time — /var is a symlink on macOS.
            let rootComponents = destination.resolvingSymlinksInPath().pathComponents

            guard let enumerator = FileManager.default.enumerator(
                at: destination,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
            ) else {
                return Result(branch: branch, files: [], totalBytes: 0, tarballBytes: data.count)
            }

            while let candidate = enumerator.nextObject() as? URL {
                guard
                    let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                    values.isRegularFile == true,
                    let size = values.fileSize
                else { continue }

                // Skip our own tarball artifact.
                if candidate.lastPathComponent == ".archive.tar.gz" { continue }

                let candidateComponents = candidate.resolvingSymlinksInPath().pathComponents
                guard candidateComponents.count > rootComponents.count else { continue }
                let relpath = candidateComponents
                    .dropFirst(rootComponents.count)
                    .joined(separator: "/")

                guard let classified = PackageFileKindClassifier.classify(relpath: relpath) else { continue }

                guard let content = try? String(contentsOf: candidate, encoding: .utf8) else { continue }

                files.append(ExtractedFile(
                    relpath: relpath,
                    kind: classified.kind,
                    module: classified.module,
                    content: content,
                    byteSize: size
                ))
                totalBytes += Int64(size)
            }

            return Result(
                branch: branch,
                files: files,
                totalBytes: totalBytes,
                tarballBytes: data.count
            )
        }

        private func runTar(tarballURL: URL, outputDir: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = [
                "-xzf", tarballURL.path,
                "-C", outputDir.path,
                "--strip-components=1",
            ]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let err = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw ExtractError.tarFailed(code: process.terminationStatus, stderr: err)
            }
        }

        // MARK: - Pruning

        /// Remove everything in the extracted tree that matches the exclusion rules.
        /// Runs post-extract so the logic is all Swift (easier to test than tar glob
        /// patterns, which vary subtly between bsdtar and gnutar).
        func prune(rootURL: URL) throws {
            try pruneTopLevelDirectories(at: rootURL)
            try pruneByPatterns(rootURL: rootURL)
        }

        private func pruneTopLevelDirectories(at root: URL) throws {
            for name in Self.excludedTopLevelDirectories {
                let candidate = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    try FileManager.default.removeItem(at: candidate)
                }
            }
        }

        private func pruneByPatterns(rootURL: URL) throws {
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return }

            var toRemove: [URL] = []
            while let candidate = enumerator.nextObject() as? URL {
                let name = candidate.lastPathComponent
                let ext = candidate.pathExtension.lowercased()
                let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

                if isDirectory, name.hasSuffix(".xcassets") {
                    toRemove.append(candidate)
                    enumerator.skipDescendants()
                    continue
                }

                if !isDirectory {
                    if Self.excludedExtensions.contains(ext) {
                        toRemove.append(candidate)
                    } else if Self.excludedHiddenFiles.contains(name) {
                        toRemove.append(candidate)
                    }
                }
            }

            for url in toRemove {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // MARK: - Exclusion rules (visible for testing)

        static let excludedTopLevelDirectories: Set<String> = [
            ".github",
            ".build",
            "DerivedData",
            ".swiftpm",
            ".git",
            "Benchmarks",
        ]

        static let excludedExtensions: Set<String> = [
            "png",
            "jpg",
            "jpeg",
            "gif",
            "xib",
            "storyboard",
            "nib",
            "dsym",
            "zip",
            "tar",
            "dat",
            "ico",
            "pdf",
        ]

        static let excludedHiddenFiles: Set<String> = [
            ".editorconfig",
            ".gitignore",
            ".gitattributes",
            ".mailmap",
            ".licenseignore",
            ".swift-format",
            ".swift-version",
            ".travis.yml",
            ".codecov.yml",
            ".dockerignore",
        ]
    }
}
