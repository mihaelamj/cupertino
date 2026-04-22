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
            public let missingManifest: Int
            public let malformedManifest: Int
            public let duration: TimeInterval

            public var discoveredCount: Int { resolvedCount - seedCount }
        }

        private let session: URLSession
        private let requestDelay: TimeInterval
        private let candidateBranches = ["HEAD", "main", "master"]

        public init(requestDelay: TimeInterval = 0.05) {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.httpAdditionalHeaders = ["User-Agent": Shared.Constants.App.userAgent]
            session = URLSession(configuration: config)
            self.requestDelay = requestDelay
        }

        /// Expand seeds into the transitive dependency closure. Returns packages
        /// keyed by normalized GitHub URL so the same repo is never duplicated.
        public func resolve(
            seeds: [PackageReference],
            onProgress: (@Sendable (String, Int, Int) -> Void)? = nil
        ) async -> (packages: [PackageReference], stats: Statistics) {
            let startedAt = Date()
            var visited: [String: PackageReference] = [:]
            var frontier: [PackageReference] = []
            var skippedNonGitHub = 0
            var missingManifest = 0
            var malformedManifest = 0

            for seed in seeds {
                let key = normalizeKey(owner: seed.owner, repo: seed.repo)
                if visited[key] == nil {
                    visited[key] = seed
                    frontier.append(seed)
                }
            }
            let seedCount = visited.count

            var processed = 0
            while !frontier.isEmpty {
                let next = frontier.removeFirst()
                processed += 1
                onProgress?("\(next.owner)/\(next.repo)", processed, processed + frontier.count)

                let resolvedURLs: [String]
                switch await fetchDependencyURLs(owner: next.owner, repo: next.repo) {
                case .success(let urls):
                    resolvedURLs = urls
                case .missing:
                    missingManifest += 1
                    continue
                case .malformed:
                    malformedManifest += 1
                    continue
                }

                for location in resolvedURLs {
                    guard let github = GitHubRepo(location: location) else {
                        skippedNonGitHub += 1
                        continue
                    }
                    let key = normalizeKey(owner: github.owner, repo: github.repo)
                    if visited[key] != nil { continue }
                    let ref = PackageReference(
                        owner: github.owner,
                        repo: github.repo,
                        url: github.canonicalURL,
                        priority: classify(owner: github.owner)
                    )
                    visited[key] = ref
                    frontier.append(ref)
                }

                if requestDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(requestDelay * 1_000_000_000))
                }
            }

            let packages = Array(visited.values).sorted { lhs, rhs in
                if lhs.owner == rhs.owner { return lhs.repo < rhs.repo }
                return lhs.owner < rhs.owner
            }
            let stats = Statistics(
                seedCount: seedCount,
                resolvedCount: packages.count,
                skippedNonGitHub: skippedNonGitHub,
                missingManifest: missingManifest,
                malformedManifest: malformedManifest,
                duration: Date().timeIntervalSince(startedAt)
            )
            return (packages, stats)
        }

        // MARK: - Manifest fetch

        private enum FetchResult {
            case success([String])
            case missing
            case malformed
        }

        /// Try Package.swift first (libraries always commit it), then Package.resolved
        /// (apps commit this; libraries typically don't). Stops at the first branch +
        /// manifest-type combination that yields parseable content.
        private func fetchDependencyURLs(owner: String, repo: String) async -> FetchResult {
            var sawMalformed = false

            for branch in candidateBranches {
                // 1. Package.swift — covers libraries.
                switch await fetch(owner: owner, repo: repo, branch: branch, file: "Package.swift") {
                case .hit(let data):
                    let urls = Self.parsePackageSwiftURLs(data)
                    if !urls.isEmpty {
                        return .success(urls)
                    }
                    // Empty result from a parseable file just means no deps — that's
                    // terminal but not an error. Fall through to Package.resolved in
                    // case the repo also commits that (rare but possible).
                case .notFound:
                    break
                case .transientError:
                    break
                }

                // 2. Package.resolved — covers apps / repos that commit the lockfile.
                switch await fetch(owner: owner, repo: repo, branch: branch, file: "Package.resolved") {
                case .hit(let data):
                    if let urls = Self.parsePackageResolvedLocations(data) {
                        return .success(urls)
                    }
                    sawMalformed = true
                case .notFound:
                    continue
                case .transientError:
                    continue
                }
            }

            return sawMalformed ? .malformed : .missing
        }

        private enum HTTPResult {
            case hit(Data)
            case notFound
            case transientError
        }

        private func fetch(owner: String, repo: String, branch: String, file: String) async -> HTTPResult {
            let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(file)")!
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    return .transientError
                }
                if http.statusCode == 200 {
                    return .hit(data)
                }
                if http.statusCode == 404 {
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
        internal static func parsePackageResolvedLocations(_ data: Data) -> [String]? {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let pins: [[String: Any]]
            if let rootPins = json["pins"] as? [[String: Any]] {
                pins = rootPins
            } else if let object = json["object"] as? [String: Any],
                      let nestedPins = object["pins"] as? [[String: Any]]
            {
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
        internal static func parsePackageSwiftURLs(_ data: Data) -> [String] {
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
        internal static func stripLineComment(_ line: Substring) -> String {
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

        /// Test hook: expose the GitHub URL parser without leaking the fileprivate struct.
        internal static func parseGitHubRepo(_ location: String) -> (owner: String, repo: String)? {
            guard let repo = GitHubRepo(location: location) else { return nil }
            return (repo.owner, repo.repo)
        }

        // MARK: - Helpers

        private func classify(owner: String) -> PackagePriority {
            if owner == Shared.Constants.GitHubOrg.apple
                || owner == Shared.Constants.GitHubOrg.swiftlang
                || owner == Shared.Constants.GitHubOrg.swiftServer
            {
                return .appleOfficial
            }
            return .ecosystem
        }

        private func normalizeKey(owner: String, repo: String) -> String {
            "\(owner.lowercased())/\(repo.lowercased())"
        }

        private func logDebug(_ message: String) {
            // Debug-only noise; keep out of default stdout. Users who want it can run
            // with CUPERTINO_DEBUG_RESOLVER=1 in the future. For now, silent.
            _ = message
        }
    }
}

// MARK: - GitHub URL parsing

private struct GitHubRepo {
    let owner: String
    let repo: String
    var canonicalURL: String { "https://github.com/\(owner)/\(repo)" }

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
