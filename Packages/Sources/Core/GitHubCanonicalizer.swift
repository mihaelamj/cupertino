import Foundation
import Shared

extension Core {
    /// Canonicalizes `(owner, repo)` pairs using `api.github.com/repos/<owner>/<repo>`,
    /// resolving GitHub's silent redirects (e.g. `apple/swift-docc` → `swiftlang/swift-docc`)
    /// so the resolver can dedupe aliases. Results are memoised in-process and persisted
    /// to `canonical-owners.json`, so subsequent runs don't re-hit the API for known repos.
    public actor GitHubCanonicalizer {
        public struct CanonicalName: Sendable, Equatable {
            public let owner: String
            public let repo: String

            public init(owner: String, repo: String) {
                self.owner = owner
                self.repo = repo
            }
        }

        private let cacheURL: URL
        private let session: URLSession
        private var cache: [String: String] = [:]
        private var dirty = false

        public init(cacheURL: URL, session: URLSession = .shared) {
            self.cacheURL = cacheURL
            self.session = session
            if let data = try? Data(contentsOf: cacheURL),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                cache = decoded
            }
        }

        /// Return the canonical owner/repo. Successful lookups (HTTP 200) are cached
        /// permanently. Transient failures (timeout, 5xx, network blip) return the
        /// input unchanged but are **not** cached — we'd rather retry on the next run
        /// than permanently record a wrong identity mapping. A confirmed 404 is
        /// cached as identity so we don't hammer a known-deleted repo.
        public func canonicalize(owner: String, repo: String) async -> CanonicalName {
            let key = Self.key(owner: owner, repo: repo)
            if let cached = cache[key], let parsed = Self.parse(cached) {
                return parsed
            }
            switch await fetchCanonical(owner: owner, repo: repo) {
            case .success(let canonical):
                cache[key] = "\(canonical.owner)/\(canonical.repo)"
                dirty = true
                return canonical
            case .notFound:
                cache[key] = "\(owner)/\(repo)"
                dirty = true
                return CanonicalName(owner: owner, repo: repo)
            case .transient:
                // No caching: the next run may well resolve it correctly, and caching
                // identity here was the root cause of the `apple/` vs `swiftlang/`
                // duplicates in the initial 0.11.0 smoke test.
                return CanonicalName(owner: owner, repo: repo)
            }
        }

        /// Flush the in-memory cache to disk. Call once at the end of a resolve so we
        /// don't write on every canonicalize. Safe to call repeatedly — no-ops when
        /// nothing has changed.
        public func persist() {
            guard dirty else { return }
            do {
                let dir = cacheURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(cache)
                try data.write(to: cacheURL)
                dirty = false
            } catch {
                // Non-fatal: cache is a lifetime optimisation, not a correctness boundary.
            }
        }

        // MARK: - HTTP

        private enum FetchOutcome {
            case success(CanonicalName)
            case notFound // 404 — confirmed-missing; safe to cache as identity
            case transient // timeout / 5xx / network error; do not cache
        }

        /// Resolve the canonical owner/repo by following GitHub's HTTP redirects on the
        /// web endpoint. `api.github.com` caps anonymous callers at 60 req/hr, which is
        /// trivially consumed by a single resolve run; `github.com/<owner>/<repo>`
        /// redirects without auth and has a far more generous limit in practice.
        /// URLSession follows the 301/302 chain automatically; the final `response.url`
        /// is what we parse.
        private func fetchCanonical(owner: String, repo: String) async -> FetchOutcome {
            guard let url = URL(string: "https://github.com/\(owner)/\(repo)") else {
                return .transient
            }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.setValue(Shared.Constants.App.userAgent, forHTTPHeaderField: "User-Agent")
            // 30s covers slow TLS handshakes under concurrent load. The previous 10s
            // was hitting transient timeouts and poisoning the cache; see #184 discussion.
            request.timeoutInterval = 30
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return .transient
                }
                if http.statusCode == 200, let finalURL = response.url,
                   let parsed = Self.parseGitHubURL(finalURL) {
                    return .success(parsed)
                }
                if http.statusCode == 404 {
                    return .notFound
                }
                return .transient
            } catch {
                return .transient
            }
        }

        static func parseGitHubURL(_ url: URL) -> CanonicalName? {
            guard url.host?.lowercased() == "github.com" else { return nil }
            let parts = url.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard parts.count >= 2 else { return nil }
            var repo = parts[1]
            if repo.hasSuffix(".git") { repo.removeLast(4) }
            guard !parts[0].isEmpty, !repo.isEmpty else { return nil }
            return CanonicalName(owner: parts[0], repo: repo)
        }

        // MARK: - Test hooks

        /// Primes the in-memory cache (tests + direct integrations that want to bypass
        /// the API for a specific pair).
        public func primeCache(inputOwner: String, inputRepo: String, canonicalOwner: String, canonicalRepo: String) {
            cache[Self.key(owner: inputOwner, repo: inputRepo)] = "\(canonicalOwner)/\(canonicalRepo)"
            dirty = true
        }

        /// Snapshot of the current in-memory cache for tests.
        public func cacheSnapshot() -> [String: String] {
            cache
        }

        // MARK: - Helpers

        static func key(owner: String, repo: String) -> String {
            "\(owner.lowercased())/\(repo.lowercased())"
        }

        static func parse(_ full: String) -> CanonicalName? {
            let parts = full.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return CanonicalName(owner: parts[0], repo: parts[1])
        }
    }
}
