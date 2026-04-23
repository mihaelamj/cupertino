import Foundation
import Shared

extension Core {
    /// Disk cache for fetched `Package.swift` / `Package.resolved` files, keyed by
    /// `(owner, repo, branch, file)`. Entries have a TTL (default 24h) so the resolver
    /// can skip the HTTP round-trip on re-runs within that window without going fully
    /// stale. The seed-checksum cache in `ResolvedPackagesStore` already prevents
    /// re-walks when inputs haven't changed; this cache helps when the seed set has
    /// grown (or `--refresh` was passed) but most upstream manifests are unchanged.
    public actor ManifestCache {
        private let rootDirectory: URL
        private let ttl: TimeInterval

        public init(
            rootDirectory: URL,
            ttl: TimeInterval = 24 * 60 * 60
        ) {
            self.rootDirectory = rootDirectory
            self.ttl = ttl
        }

        /// Return cached bytes if the entry is fresh. Missing, expired, or marked as a
        /// 404 → nil (caller re-fetches).
        public func read(
            owner: String,
            repo: String,
            branch: String,
            file: String
        ) -> Data? {
            let fileURL = entryURL(owner: owner, repo: repo, branch: branch, file: file)
            guard
                FileManager.default.fileExists(atPath: fileURL.path),
                let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                let modified = attrs[.modificationDate] as? Date,
                Date().timeIntervalSince(modified) < ttl
            else {
                return nil
            }
            // Zero-byte file is our "sentinel for 404 miss"; don't surface as a hit.
            if (attrs[.size] as? Int) == 0 {
                return nil
            }
            return try? Data(contentsOf: fileURL)
        }

        /// Cache a 200 OK body. Non-fatal on write failure (cache is opportunistic).
        public func write(
            _ data: Data,
            owner: String,
            repo: String,
            branch: String,
            file: String
        ) {
            let fileURL = entryURL(owner: owner, repo: repo, branch: branch, file: file)
            do {
                try ensureDirectory(for: fileURL)
                try data.write(to: fileURL)
            } catch {
                // Cache is an optimisation, not a correctness boundary.
            }
        }

        /// Cache a 404 as a zero-byte sentinel so we don't re-hit a known-missing file
        /// within the TTL window. Same file convention as the hit cache — the reader
        /// treats zero-byte as "not a hit", and the write touches mtime so the sentinel
        /// ages out on the normal schedule.
        public func writeMiss(
            owner: String,
            repo: String,
            branch: String,
            file: String
        ) {
            let fileURL = entryURL(owner: owner, repo: repo, branch: branch, file: file)
            do {
                try ensureDirectory(for: fileURL)
                try Data().write(to: fileURL)
            } catch {
                // Non-fatal.
            }
        }

        /// Visible for testing: expose the on-disk location so tests can assert
        /// cache-hit behaviour without probing the actor's internals.
        public func entryURL(
            owner: String,
            repo: String,
            branch: String,
            file: String
        ) -> URL {
            rootDirectory
                .appendingPathComponent(owner.lowercased())
                .appendingPathComponent(repo.lowercased())
                .appendingPathComponent(branch)
                .appendingPathComponent(file)
        }

        private func ensureDirectory(for fileURL: URL) throws {
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
