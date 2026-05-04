import Foundation
import Shared

extension Core {
    /// One entry in the resolved closure. Seeds list themselves as their own parent;
    /// transitively-discovered packages list every seed whose dependency graph reached
    /// them (can be multiple, which is how the store records a shared dependency).
    public struct ResolvedPackage: Codable, Sendable, Hashable {
        public let owner: String
        public let repo: String
        public let url: String
        public let priority: PackagePriority
        public let parents: [String]

        public init(
            owner: String,
            repo: String,
            url: String,
            priority: PackagePriority,
            parents: [String]
        ) {
            self.owner = owner
            self.repo = repo
            self.url = url
            self.priority = priority
            self.parents = parents
        }
    }

    /// Persisted cache of the last transitive resolution. Lives at
    /// `~/.cupertino/resolved-packages.json`. The seed checksum invalidates the cache
    /// automatically on any edit to `selected-packages.json` or `excluded-packages.json`;
    /// `--refresh` invalidates it manually for upstream-drift recaptures.
    public struct ResolvedPackagesStore: Codable, Sendable {
        public let schemaVersion: Int
        public let generatedAt: Date
        public let cupertinoVersion: String
        public let seedChecksum: String
        public let packages: [ResolvedPackage]

        public static let currentSchemaVersion = 1

        public init(
            schemaVersion: Int = ResolvedPackagesStore.currentSchemaVersion,
            generatedAt: Date = Date(),
            cupertinoVersion: String,
            seedChecksum: String,
            packages: [ResolvedPackage]
        ) {
            self.schemaVersion = schemaVersion
            self.generatedAt = generatedAt
            self.cupertinoVersion = cupertinoVersion
            self.seedChecksum = seedChecksum
            self.packages = packages
        }

        // MARK: - Disk I/O

        public static func load(from fileURL: URL) -> ResolvedPackagesStore? {
            guard
                let data = try? Data(contentsOf: fileURL),
                let decoded = try? decoder().decode(ResolvedPackagesStore.self, from: data),
                decoded.schemaVersion == currentSchemaVersion
            else {
                return nil
            }
            return decoded
        }

        public func write(to fileURL: URL) throws {
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try Self.encoder().encode(self)
            try data.write(to: fileURL)
        }

        // MARK: - Checksum over seed + exclusion inputs

        /// Canonical representation of the inputs that influence a resolution. Any
        /// change here must invalidate the cache. Sort for stability so cosmetic
        /// reorderings in the seed file don't trigger a needless re-resolve.
        public static func checksum(
            seeds: [PackageReference],
            exclusions: Set<String>
        ) -> String {
            let seedEntries = seeds
                .map { "\($0.owner.lowercased())/\($0.repo.lowercased())" }
                .sorted()
            let exclusionEntries = exclusions.sorted()
            var hasher = SimpleHasher()
            hasher.combine("seeds")
            for entry in seedEntries {
                hasher.combine(entry)
            }
            hasher.combine("exclusions")
            for entry in exclusionEntries {
                hasher.combine(entry)
            }
            return hasher.finalize()
        }

        // MARK: - Codable helpers

        private static func encoder() -> JSONEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }

        private static func decoder() -> JSONDecoder {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }
    }
}

// MARK: - Simple FNV-1a hasher

/// Minimal string-only hasher used for the seed-checksum so we don't have to depend
/// on CryptoKit (which restricts availability). FNV-1a 64-bit is plenty for cache
/// invalidation — collisions are a performance nuisance, not a correctness hazard.
private struct SimpleHasher {
    private var value: UInt64 = 0xcbf29ce484222325
    private let prime: UInt64 = 0x100000001b3

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* prime
        }
        // Field separator so ["ab", "c"] and ["a", "bc"] hash differently.
        value ^= 0x1f
        value = value &* prime
    }

    func finalize() -> String {
        String(format: "fnv1a64:%016x", value)
    }
}
