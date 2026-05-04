// swiftlint:disable identifier_name
// swiftlint:disable function_body_length type_body_length
import Foundation
import Logging
import Shared

extension Core {
    /// Walks each seed repo's dependency graph via raw.githubusercontent.com and returns
    /// the transitive closure of GitHub-hosted Swift package references.
    ///
    /// Primary source: `Package.swift` (libraries always commit it, and the `.package(url:)`
    /// declarations are trivial to regex-extract). Fallback: `Package.resolved` (committed
    /// by apps, not libraries). Non-GitHub URLs (GitLab, self-hosted, SPM registry) are
    /// counted and skipped.
    public actor PackageDependencyResolver {
        public struct Statistics: Sendable {
            public let seedCount: Int
            public let resolvedCount: Int
            public let skippedNonGitHub: Int
            public let skippedRegistry: Int
            public let missingManifest: Int
            public let malformedManifest: Int
            public let excludedCount: Int
            public let duration: TimeInterval

            public var discoveredCount: Int {
                resolvedCount - seedCount
            }
        }

        private let session: URLSession
        private let requestDelay: TimeInterval
        private let concurrency: Int
        private let candidateBranches = ["HEAD", "main", "master"]
        private let canonicalizer: GitHubCanonicalizer?
        private let exclusions: Set<String>
        private let manifestCache: ManifestCache?

        public init(
            canonicalizer: GitHubCanonicalizer? = nil,
            exclusions: Set<String> = [],
            manifestCache: ManifestCache? = nil,
            concurrency: Int = 10,
            requestDelay: TimeInterval = 0.05
        ) {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.httpAdditionalHeaders = ["User-Agent": Shared.Constants.App.userAgent]
            session = URLSession(configuration: config)
            self.canonicalizer = canonicalizer
            self.exclusions = exclusions
            self.manifestCache = manifestCache
            self.concurrency = max(1, concurrency)
            self.requestDelay = requestDelay
        }

        /// Expand seeds into the transitive dependency closure. Each returned
        /// `ResolvedPackage` carries the set of seeds whose graph reached it; seeds
        /// list themselves. Canonicalization dedupes GitHub redirects (so
        /// `apple/swift-docc` and `swiftlang/swift-docc` collapse into one entry);
        /// exclusions drop matched canonical names before adding them to the frontier.
        public func resolve(
            seeds: [PackageReference],
            onProgress: (@Sendable (String, Int, Int) -> Void)? = nil
        ) async -> (packages: [ResolvedPackage], stats: Statistics) {
            let startedAt = Date()
            var visited: [String: ResolvedPackage] = [:]
            var frontier: [(owner: String, repo: String, seedOrigin: String)] = []
            var skippedNonGitHub = 0
            var missingManifest = 0
            var malformedManifest = 0
            var excludedCount = 0

            for seed in seeds {
                let canonical = await canonicalize(owner: seed.owner, repo: seed.repo)
                let key = Self.dedupeKey(owner: canonical.owner, repo: canonical.repo)
                if exclusions.contains(key) {
                    excludedCount += 1
                    continue
                }
                if visited[key] != nil { continue }
                let seedOrigin = key
                visited[key] = ResolvedPackage(
                    owner: canonical.owner,
                    repo: canonical.repo,
                    url: "https://github.com/\(canonical.owner)/\(canonical.repo)",
                    priority: classify(owner: canonical.owner),
                    parents: [seedOrigin]
                )
                frontier.append((canonical.owner, canonical.repo, seedOrigin))
            }
            let seedCount = visited.count

            var processed = 0
            var skippedRegistry = 0
            while !frontier.isEmpty {
                let batchSize = min(concurrency, frontier.count)
                let batch = Array(frontier.prefix(batchSize))
                frontier.removeFirst(batchSize)

                let results: [(String, String, String, FetchResult)] = await withTaskGroup(
                    of: (String, String, String, FetchResult).self
                ) { [session, candidateBranches, manifestCache] group in
                    for item in batch {
                        group.addTask {
                            let result = await Self.fetchDependencyURLs(
                                session: session,
                                candidateBranches: candidateBranches,
                                cache: manifestCache,
                                owner: item.owner,
                                repo: item.repo
                            )
                            return (item.owner, item.repo, item.seedOrigin, result)
                        }
                    }
                    var collected: [(String, String, String, FetchResult)] = []
                    for await r in group {
                        collected.append(r)
                    }
                    return collected
                }

                for (ownerIn, repoIn, seedOrigin, result) in results {
                    processed += 1
                    onProgress?("\(ownerIn)/\(repoIn)", processed, processed + frontier.count)

                    let resolved: FetchSuccess
                    switch result {
                    case .success(let success):
                        resolved = success
                    case .missing:
                        missingManifest += 1
                        continue
                    case .malformed:
                        malformedManifest += 1
                        continue
                    }

                    skippedRegistry += resolved.registryIdentifierCount

                    for location in resolved.dependencyURLs {
                        guard let github = GitHubRepo(location: location) else {
                            skippedNonGitHub += 1
                            continue
                        }
                        let canonical = await canonicalize(owner: github.owner, repo: github.repo)
                        let key = Self.dedupeKey(owner: canonical.owner, repo: canonical.repo)
                        if exclusions.contains(key) {
                            excludedCount += 1
                            continue
                        }
                        if var existing = visited[key] {
                            if !existing.parents.contains(seedOrigin) {
                                existing = ResolvedPackage(
                                    owner: existing.owner,
                                    repo: existing.repo,
                                    url: existing.url,
                                    priority: existing.priority,
                                    parents: existing.parents + [seedOrigin]
                                )
                                visited[key] = existing
                            }
                            continue
                        }
                        visited[key] = ResolvedPackage(
                            owner: canonical.owner,
                            repo: canonical.repo,
                            url: "https://github.com/\(canonical.owner)/\(canonical.repo)",
                            priority: classify(owner: canonical.owner),
                            parents: [seedOrigin]
                        )
                        frontier.append((canonical.owner, canonical.repo, seedOrigin))
                    }
                }

                if requestDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(requestDelay * 1000000000))
                }
            }

            await canonicalizer?.persist()

            let packages = Array(visited.values).sorted { lhs, rhs in
                if lhs.owner == rhs.owner { return lhs.repo < rhs.repo }
                return lhs.owner < rhs.owner
            }
            let stats = Statistics(
                seedCount: seedCount,
                resolvedCount: packages.count,
                skippedNonGitHub: skippedNonGitHub,
                skippedRegistry: skippedRegistry,
                missingManifest: missingManifest,
                malformedManifest: malformedManifest,
                excludedCount: excludedCount,
                duration: Date().timeIntervalSince(startedAt)
            )
            return (packages, stats)
        }

        // MARK: - Canonicalisation

        private func canonicalize(owner: String, repo: String) async -> (owner: String, repo: String) {
            guard let canonicalizer else { return (owner, repo) }
            let canonical = await canonicalizer.canonicalize(owner: owner, repo: repo)
            return (canonical.owner, canonical.repo)
        }

        static func dedupeKey(owner: String, repo: String) -> String {
            "\(owner.lowercased())/\(repo.lowercased())"
        }

        // MARK: - Manifest fetch

        struct FetchSuccess: Sendable {
            let dependencyURLs: [String]
            let registryIdentifierCount: Int
        }

        enum FetchResult: Sendable {
            case success(FetchSuccess)
            case missing
            case malformed
        }

        private enum HTTPResult {
            case hit(Data)
            case notFound
            case transientError
        }

        /// Static so batches of tasks in a TaskGroup can run in parallel without
        /// serialising through the actor. Walks Package.swift first (libraries commit
        /// it, so most seeds are covered here), then Package.resolved as a fallback
        /// (apps commit the lockfile, libraries don't).
        static func fetchDependencyURLs(
            session: URLSession,
            candidateBranches: [String],
            cache: ManifestCache?,
            owner: String,
            repo: String
        ) async -> FetchResult {
            var sawMalformed = false

            for branch in candidateBranches {
                switch await fetchManifest(
                    session: session,
                    cache: cache,
                    owner: owner,
                    repo: repo,
                    branch: branch,
                    file: "Package.swift"
                ) {
                case .hit(let data):
                    // Successful fetch is terminal even if the package declares no
                    // dependencies or only registry-id deps: we know the manifest
                    // exists, so don't count it as missing.
                    let urls = parsePackageSwiftURLs(data)
                    let registryCount = parsePackageSwiftRegistryIdCount(data)
                    return .success(FetchSuccess(
                        dependencyURLs: urls,
                        registryIdentifierCount: registryCount
                    ))
                case .notFound, .transientError:
                    break
                }

                switch await fetchManifest(
                    session: session,
                    cache: cache,
                    owner: owner,
                    repo: repo,
                    branch: branch,
                    file: "Package.resolved"
                ) {
                case .hit(let data):
                    if let urls = parsePackageResolvedLocations(data) {
                        return .success(FetchSuccess(
                            dependencyURLs: urls,
                            registryIdentifierCount: 0
                        ))
                    }
                    sawMalformed = true
                case .notFound, .transientError:
                    continue
                }
            }

            return sawMalformed ? .malformed : .missing
        }

        private static func fetchManifest(
            session: URLSession,
            cache: ManifestCache?,
            owner: String,
            repo: String,
            branch: String,
            file: String
        ) async -> HTTPResult {
            if let cache, let cached = await cache.read(owner: owner, repo: repo, branch: branch, file: file) {
                return .hit(cached)
            }
            let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(file)")!
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    return .transientError
                }
                if http.statusCode == 200 {
                    await cache?.write(data, owner: owner, repo: repo, branch: branch, file: file)
                    return .hit(data)
                }
                if http.statusCode == 404 {
                    await cache?.writeMiss(owner: owner, repo: repo, branch: branch, file: file)
                    return .notFound
                }
                return .transientError
            } catch {
                return .transientError
            }
        }

        /// Parse both v1 (`pins[].repositoryURL` or nested `pins[].object.repositoryURL`)
        /// and v2/v3 (`pins[].location`) formats. Returns nil when the JSON root isn't a
        /// dict or the `pins` key is missing / wrong-typed; returns an empty array when
        /// `pins` is present but empty.
        static func parsePackageResolvedLocations(_ data: Data) -> [String]? {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let pins: [[String: Any]]
            if let rootPins = json["pins"] as? [[String: Any]] {
                pins = rootPins
            } else if let object = json["object"] as? [String: Any],
                      let nestedPins = object["pins"] as? [[String: Any]] {
                pins = nestedPins
            } else {
                return nil
            }
            var out: [String] = []
            for pin in pins {
                if let location = pin["location"] as? String {
                    out.append(location)
                } else if let repositoryURL = pin["repositoryURL"] as? String {
                    out.append(repositoryURL)
                } else if let object = pin["object"] as? [String: Any],
                          let repositoryURL = object["repositoryURL"] as? String {
                    out.append(repositoryURL)
                }
            }
            return out
        }

        /// Extract dependency URLs from a Package.swift manifest by regex-matching
        /// `.package(...url: "..."...)` declarations. Handles single-line and multi-line
        /// calls (`.dotMatchesLineSeparators`), both `.package(url: "…", …)` and the
        /// legacy `.package(name: "…", url: "…", …)` form. Ignores `.package(path: "…")`
        /// since those are local deps. Commented-out lines (`// .package(…)`) are
        /// filtered before matching. Always returns an array — empty means the file was
        /// readable but had no GitHub-style URL declarations (or wasn't a manifest at
        /// all, which is indistinguishable for our purposes).
        static func parsePackageSwiftURLs(_ data: Data) -> [String] {
            guard let source = String(data: data, encoding: .utf8) else {
                return []
            }
            let uncommented = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(Self.stripLineComment)
                .joined(separator: "\n")

            // `[^)]*?` is enough in practice: `url:` always appears before any nested
            // `)` (version predicates like `.upToNextMajor(from: "…")` come after the
            // URL in every standard SPM manifest). Captures the URL string literal.
            let pattern = #"\.package\s*\(\s*[^)]*?\burl\s*:\s*"([^"]+)""#
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators]
            ) else {
                return []
            }
            let nsRange = NSRange(uncommented.startIndex..<uncommented.endIndex, in: uncommented)
            var urls: [String] = []
            regex.enumerateMatches(in: uncommented, options: [], range: nsRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 2,
                      let range = Range(match.range(at: 1), in: uncommented)
                else {
                    return
                }
                urls.append(String(uncommented[range]))
            }
            return urls
        }

        /// Strip a `//` line comment from a single line, respecting string literals so
        /// `https://github.com/...` inside a `"…"` string is NOT treated as a comment.
        /// Naive `"…"` string tracking — doesn't need to handle escaped quotes because
        /// SwiftPM manifests almost never embed them in URLs or package names.
        static func stripLineComment(_ line: Substring) -> String {
            var result = ""
            var inString = false
            var i = line.startIndex
            while i < line.endIndex {
                let ch = line[i]
                if ch == "\"" {
                    inString.toggle()
                    result.append(ch)
                } else if !inString, ch == "/" {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "/" {
                        break
                    }
                    result.append(ch)
                } else {
                    result.append(ch)
                }
                i = line.index(after: i)
            }
            return result
        }

        /// Count `.package(id: "scope.name", ...)` registry-identifier dependencies in a
        /// Package.swift. We don't resolve them to source URLs (the SwiftPM registry
        /// protocol is scope-specific and out of scope for this resolver); we just count
        /// them so stats can surface that some deps exist but weren't walked.
        static func parsePackageSwiftRegistryIdCount(_ data: Data) -> Int {
            guard let source = String(data: data, encoding: .utf8) else { return 0 }
            let uncommented = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(stripLineComment)
                .joined(separator: "\n")
            let pattern = #"\.package\s*\(\s*[^)]*?\bid\s*:\s*"([^"]+)""#
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators]
            ) else { return 0 }
            let range = NSRange(uncommented.startIndex..<uncommented.endIndex, in: uncommented)
            return regex.numberOfMatches(in: uncommented, options: [], range: range)
        }

        /// Test hook: expose the GitHub URL parser without leaking the fileprivate struct.
        static func parseGitHubRepo(_ location: String) -> (owner: String, repo: String)? {
            guard let repo = GitHubRepo(location: location) else { return nil }
            return (repo.owner, repo.repo)
        }

        // MARK: - Helpers

        private func classify(owner: String) -> PackagePriority {
            if owner == Shared.Constants.GitHubOrg.apple
                || owner == Shared.Constants.GitHubOrg.swiftlang
                || owner == Shared.Constants.GitHubOrg.swiftServer {
                return .appleOfficial
            }
            return .ecosystem
        }
    }
}

// MARK: - GitHub URL parsing

private struct GitHubRepo {
    let owner: String
    let repo: String
    var canonicalURL: String {
        "https://github.com/\(owner)/\(repo)"
    }

    /// Accepts common GitHub URL shapes:
    ///   https://github.com/owner/repo(.git)?
    ///   git@github.com:owner/repo(.git)?
    ///   https://github.com/owner/repo/
    /// Returns nil for non-GitHub hosts (GitLab, Bitbucket, self-hosted).
    init?(location raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        let path: String
        if let range = lower.range(of: "github.com/") {
            path = String(trimmed[range.upperBound...])
        } else if let range = lower.range(of: "github.com:") {
            path = String(trimmed[range.upperBound...])
        } else {
            return nil
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 2 else { return nil }
        let owner = components[0]
        var repo = components[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }

        // Reject characters that aren't valid in a GitHub slug.
        let invalid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").inverted
        guard owner.rangeOfCharacter(from: invalid) == nil,
              repo.rangeOfCharacter(from: invalid) == nil,
              !owner.isEmpty, !repo.isEmpty
        else {
            return nil
        }
        self.owner = owner
        self.repo = repo
    }
}
