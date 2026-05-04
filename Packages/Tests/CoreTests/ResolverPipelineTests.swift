// swiftlint:disable identifier_name use_data_constructor_over_string_member non_optional_string_data_conversion
@testable import Core
import Foundation
import Shared
import Testing

// MARK: - Checksum stability

@Test("ResolvedPackagesStore.checksum: same inputs yield same checksum")
func checksumStable() throws {
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "swift-nio", url: "https://github.com/apple/swift-nio", priority: .appleOfficial),
        .init(owner: "vapor", repo: "vapor", url: "https://github.com/vapor/vapor", priority: .ecosystem),
    ]
    let a = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: ["foo/bar"])
    let b = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: ["foo/bar"])
    #expect(a == b)
}

@Test("ResolvedPackagesStore.checksum: reordering seeds does not change checksum")
func checksumSeedOrderAgnostic() throws {
    let a = Core.ResolvedPackagesStore.checksum(
        seeds: [
            .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
            .init(owner: "vapor", repo: "vapor", url: "", priority: .ecosystem),
        ],
        exclusions: []
    )
    let b = Core.ResolvedPackagesStore.checksum(
        seeds: [
            .init(owner: "vapor", repo: "vapor", url: "", priority: .ecosystem),
            .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
        ],
        exclusions: []
    )
    #expect(a == b)
}

@Test("ResolvedPackagesStore.checksum: adding a seed changes the checksum")
func checksumAddedSeedInvalidates() throws {
    let base: [PackageReference] = [
        .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
    ]
    let extended = base + [
        .init(owner: "vapor", repo: "vapor", url: "", priority: .ecosystem),
    ]
    let a = Core.ResolvedPackagesStore.checksum(seeds: base, exclusions: [])
    let b = Core.ResolvedPackagesStore.checksum(seeds: extended, exclusions: [])
    #expect(a != b)
}

@Test("ResolvedPackagesStore.checksum: adding an exclusion changes the checksum")
func checksumAddedExclusionInvalidates() throws {
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
    ]
    let a = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: [])
    let b = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: ["foo/bar"])
    #expect(a != b)
}

@Test("ResolvedPackagesStore.checksum: seed vs exclusion separation")
func checksumSeedExclusionSeparated() throws {
    // If we didn't separate the two, swapping a seed for an exclusion of the same
    // owner/repo would collide. Confirm it doesn't.
    let seedA = Core.ResolvedPackagesStore.checksum(
        seeds: [.init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial)],
        exclusions: []
    )
    let seedB = Core.ResolvedPackagesStore.checksum(
        seeds: [],
        exclusions: ["apple/swift-nio"]
    )
    #expect(seedA != seedB)
}

// MARK: - ResolvedPackagesStore round-trip

@Test("ResolvedPackagesStore: write + load round-trips")
func storeRoundTrip() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("resolved-packages.json")
    let generatedAt = Date(timeIntervalSince1970: 1700000000)
    let store = Core.ResolvedPackagesStore(
        generatedAt: generatedAt,
        cupertinoVersion: "0.11.0",
        seedChecksum: "fnv1a64:deadbeefcafebabe",
        packages: [
            Core.ResolvedPackage(
                owner: "apple",
                repo: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                priority: .appleOfficial,
                parents: ["apple/swift-nio"]
            ),
            Core.ResolvedPackage(
                owner: "swift-server",
                repo: "swift-service-lifecycle",
                url: "https://github.com/swift-server/swift-service-lifecycle",
                priority: .appleOfficial,
                parents: ["vapor/vapor", "hummingbird-project/hummingbird"]
            ),
        ]
    )
    try store.write(to: fileURL)
    let loaded = try #require(Core.ResolvedPackagesStore.load(from: fileURL))
    #expect(loaded.schemaVersion == Core.ResolvedPackagesStore.currentSchemaVersion)
    #expect(loaded.cupertinoVersion == "0.11.0")
    #expect(loaded.seedChecksum == "fnv1a64:deadbeefcafebabe")
    #expect(loaded.packages.count == 2)
    #expect(loaded.packages[1].parents.contains("vapor/vapor"))
    #expect(loaded.packages[1].parents.contains("hummingbird-project/hummingbird"))
}

@Test("ResolvedPackagesStore: missing file returns nil (fresh install)")
func storeMissingFileReturnsNil() throws {
    let path = URL(fileURLWithPath: "/tmp/cupertino-nonexistent-\(UUID().uuidString).json")
    #expect(Core.ResolvedPackagesStore.load(from: path) == nil)
}

// MARK: - ExclusionList

@Test("ExclusionList: absent file returns empty set")
func exclusionListAbsent() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-excl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    #expect(Core.ExclusionList.load(from: tempDir).isEmpty)
}

@Test("ExclusionList: loads and normalises entries")
func exclusionListLoads() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-excl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let fileURL = tempDir.appendingPathComponent(Shared.Constants.FileName.excludedPackages)
    let json = #"[" APPLE/Swift-NIO ", "vapor/vapor"]"#.data(using: .utf8)!
    try json.write(to: fileURL)
    let excluded = Core.ExclusionList.load(from: tempDir)
    #expect(excluded.contains("apple/swift-nio"))
    #expect(excluded.contains("vapor/vapor"))
    #expect(excluded.count == 2)
}

@Test("ExclusionList: malformed JSON returns empty set")
func exclusionListMalformed() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-excl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let fileURL = tempDir.appendingPathComponent(Shared.Constants.FileName.excludedPackages)
    try "not a json array".data(using: .utf8)!.write(to: fileURL)
    #expect(Core.ExclusionList.load(from: tempDir).isEmpty)
}

// MARK: - Canonicalizer disk cache

@Test("GitHubCanonicalizer: cache-hit avoids network")
func canonicalizerCacheHit() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-canon-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")

    // Seed the cache file directly so the canonicalizer should NOT hit the network.
    let seed = ["apple/swift-docc": "swiftlang/swift-docc"]
    let data = try JSONEncoder().encode(seed)
    try data.write(to: cacheURL)

    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    let canonical = await canonicalizer.canonicalize(owner: "apple", repo: "swift-docc")
    #expect(canonical.owner == "swiftlang")
    #expect(canonical.repo == "swift-docc")
}

@Test("GitHubCanonicalizer: primeCache + persist round-trips")
func canonicalizerPersistRoundTrip() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-canon-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")

    let c1 = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    await c1.primeCache(
        inputOwner: "apple", inputRepo: "swift-docc",
        canonicalOwner: "swiftlang", canonicalRepo: "swift-docc"
    )
    await c1.persist()

    // New canonicalizer reads the persisted cache from disk.
    let c2 = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    let canonical = await c2.canonicalize(owner: "apple", repo: "swift-docc")
    #expect(canonical.owner == "swiftlang")
    #expect(canonical.repo == "swift-docc")
    let snapshot = await c2.cacheSnapshot()
    #expect(snapshot["apple/swift-docc"] == "swiftlang/swift-docc")
}

// MARK: - Resolver provenance + canonicalization

@Test("Resolver: seed lists itself as its only parent")
func resolverSeedIsSelfParent() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")
    // Prime the canonicalizer so we don't hit the network: canonical == input.
    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    await canonicalizer.primeCache(
        inputOwner: "apple", inputRepo: "only-seed",
        canonicalOwner: "apple", canonicalRepo: "only-seed"
    )

    let resolver = Core.PackageDependencyResolver(canonicalizer: canonicalizer)
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "only-seed", url: "https://github.com/apple/only-seed", priority: .appleOfficial),
    ]
    // No Package.swift will be found for a fake repo → missing manifest, seed still
    // appears in output with self as parent.
    let (packages, stats) = await resolver.resolve(seeds: seeds)
    #expect(stats.seedCount == 1)
    #expect(packages.count == 1)
    #expect(packages[0].parents == ["apple/only-seed"])
}

@Test("Resolver: exclusion list drops the seed entirely")
func resolverExcludesSeed() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")
    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    await canonicalizer.primeCache(
        inputOwner: "apple", inputRepo: "only-seed",
        canonicalOwner: "apple", canonicalRepo: "only-seed"
    )

    let resolver = Core.PackageDependencyResolver(
        canonicalizer: canonicalizer,
        exclusions: ["apple/only-seed"]
    )
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "only-seed", url: "https://github.com/apple/only-seed", priority: .appleOfficial),
    ]
    let (packages, stats) = await resolver.resolve(seeds: seeds)
    #expect(packages.isEmpty)
    #expect(stats.excludedCount == 1)
    #expect(stats.seedCount == 0)
}

// MARK: - SPM registry id parsing

@Test("parsePackageSwiftRegistryIdCount: counts single .package(id:) call")
func parseRegistryIdSingle() throws {
    let source = """
    dependencies: [
        .package(id: "apple.swift-nio", from: "2.0.0"),
    ]
    """.data(using: .utf8)!
    #expect(Core.PackageDependencyResolver.parsePackageSwiftRegistryIdCount(source) == 1)
}

@Test("parsePackageSwiftRegistryIdCount: counts multiple .package(id:) calls")
func parseRegistryIdMultiple() throws {
    let source = """
    dependencies: [
        .package(id: "apple.swift-nio", from: "2.0.0"),
        .package(id: "apple.swift-log", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    ]
    """.data(using: .utf8)!
    #expect(Core.PackageDependencyResolver.parsePackageSwiftRegistryIdCount(source) == 2)
}

@Test("parsePackageSwiftRegistryIdCount: ignores commented-out registry id")
func parseRegistryIdCommented() throws {
    let source = """
    dependencies: [
        // .package(id: "apple.swift-atomics", from: "1.0.0"),
        .package(id: "apple.swift-nio", from: "2.0.0"),
    ]
    """.data(using: .utf8)!
    #expect(Core.PackageDependencyResolver.parsePackageSwiftRegistryIdCount(source) == 1)
}

@Test("parsePackageSwiftRegistryIdCount: no registry ids in url-only manifest")
func parseRegistryIdNoneWhenUrlOnly() throws {
    let source = """
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
    ]
    """.data(using: .utf8)!
    #expect(Core.PackageDependencyResolver.parsePackageSwiftRegistryIdCount(source) == 0)
}

// MARK: - ManifestCache

@Test("ManifestCache: fresh write returns bytes on read")
func manifestCacheWriteRead() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = Core.ManifestCache(rootDirectory: tempDir, ttl: 60)
    let payload = "hello".data(using: .utf8)!
    await cache.write(payload, owner: "apple", repo: "swift-nio", branch: "main", file: "Package.swift")

    let cached = await cache.read(owner: "apple", repo: "swift-nio", branch: "main", file: "Package.swift")
    #expect(cached == payload)
}

@Test("ManifestCache: missing entry returns nil")
func manifestCacheMiss() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = Core.ManifestCache(rootDirectory: tempDir, ttl: 60)
    let cached = await cache.read(owner: "apple", repo: "swift-nio", branch: "main", file: "Package.swift")
    #expect(cached == nil)
}

@Test("ManifestCache: expired entry returns nil")
func manifestCacheExpired() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = Core.ManifestCache(rootDirectory: tempDir, ttl: 0.001)
    let payload = "hello".data(using: .utf8)!
    await cache.write(payload, owner: "apple", repo: "swift-nio", branch: "main", file: "Package.swift")

    // Wait long enough to age past the 1ms TTL.
    try await Task.sleep(nanoseconds: 50000000) // 50ms

    let cached = await cache.read(owner: "apple", repo: "swift-nio", branch: "main", file: "Package.swift")
    #expect(cached == nil)
}

@Test("ManifestCache: writeMiss sentinel is not surfaced as a hit")
func manifestCacheMissSentinel() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-cache-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = Core.ManifestCache(rootDirectory: tempDir, ttl: 60)
    await cache.writeMiss(owner: "apple", repo: "not-exist", branch: "main", file: "Package.swift")

    let cached = await cache.read(owner: "apple", repo: "not-exist", branch: "main", file: "Package.swift")
    #expect(cached == nil)
}

// MARK: - Canonical dedupe

// MARK: - parseGitHubURL (pure helper)

@Test("parseGitHubURL: plain github.com/owner/repo")
func parseGitHubURLPlain() throws {
    let url = URL(string: "https://github.com/apple/swift-nio")!
    let parsed = try #require(Core.GitHubCanonicalizer.parseGitHubURL(url))
    #expect(parsed.owner == "apple")
    #expect(parsed.repo == "swift-nio")
}

@Test("parseGitHubURL: strips trailing .git")
func parseGitHubURLStripsGitSuffix() throws {
    let url = URL(string: "https://github.com/apple/swift-nio.git")!
    let parsed = try #require(Core.GitHubCanonicalizer.parseGitHubURL(url))
    #expect(parsed.owner == "apple")
    #expect(parsed.repo == "swift-nio")
}

@Test("parseGitHubURL: strips tree/branch suffixes")
func parseGitHubURLStripsExtraPath() throws {
    let url = URL(string: "https://github.com/apple/swift-nio/tree/main")!
    let parsed = try #require(Core.GitHubCanonicalizer.parseGitHubURL(url))
    #expect(parsed.owner == "apple")
    #expect(parsed.repo == "swift-nio")
}

@Test("parseGitHubURL: rejects non-github host")
func parseGitHubURLRejectsOtherHosts() throws {
    let url = URL(string: "https://gitlab.com/apple/swift-nio")!
    #expect(Core.GitHubCanonicalizer.parseGitHubURL(url) == nil)
}

@Test("parseGitHubURL: rejects path with only owner")
func parseGitHubURLRejectsSingleComponent() throws {
    let url = URL(string: "https://github.com/apple")!
    #expect(Core.GitHubCanonicalizer.parseGitHubURL(url) == nil)
}

// MARK: - Integration (network required)

@Suite("Resolver network integration", .tags(.integration), .serialized)
struct ResolverNetworkIntegration {
    /// The reason the canonicaliser exists: catch GitHub renames so `apple/swift-docc`
    /// and `swiftlang/swift-docc` (same repo via redirect) dedupe into one closure
    /// entry. Live fire against the real redirect chain. If GitHub ever un-renames
    /// swift-docc or renames it again this test will drift and signal exactly that.
    @Test("Canonicalizer: renamed repo follows GitHub's redirect")
    func canonicalizerFollowsRename() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-canon-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")

        let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
        let canonical = await canonicalizer.canonicalize(owner: "apple", repo: "swift-docc")
        #expect(canonical.owner == "swiftlang")
        #expect(canonical.repo == "swift-docc")
    }

    /// Resolve a single real seed and assert the closure contains its documented
    /// Package.swift dependencies. swift-composable-architecture is a stable choice:
    /// it lives in one repo, has a handful of well-known pointfreeco deps, and its
    /// manifest is easy to eyeball.
    @Test("Resolver: real seed walks Package.swift dependencies")
    func resolverRealSeedClosure() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-resolve-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let canonicalizer = Core.GitHubCanonicalizer(
            cacheURL: tempDir.appendingPathComponent("canonical-owners.json")
        )
        let manifestCache = Core.ManifestCache(
            rootDirectory: tempDir.appendingPathComponent("manifests")
        )
        let resolver = Core.PackageDependencyResolver(
            canonicalizer: canonicalizer,
            manifestCache: manifestCache,
            concurrency: 4
        )

        let seeds: [PackageReference] = [
            .init(
                owner: "pointfreeco",
                repo: "swift-composable-architecture",
                url: "https://github.com/pointfreeco/swift-composable-architecture",
                priority: .ecosystem
            ),
        ]
        let (packages, stats) = await resolver.resolve(seeds: seeds)
        #expect(stats.seedCount == 1)
        #expect(stats.discoveredCount > 0)
        #expect(stats.missingManifest == 0)

        let names = Set(packages.map { "\($0.owner)/\($0.repo)".lowercased() })
        // These are long-standing TCA deps; if any of the three go missing the test
        // should still reveal something useful from the assertion message.
        #expect(names.contains("pointfreeco/swift-composable-architecture"))
        #expect(names.contains("pointfreeco/swift-dependencies"))
        #expect(names.contains("pointfreeco/swift-custom-dump"))
    }

    /// Second resolve in a row should hit the ManifestCache for manifests already
    /// fetched, so it's much faster and has no misses on repos the first run saw.
    /// We don't assert a strict duration (CI variance), but we assert that the second
    /// run doesn't record any missing manifests for a seed whose first run succeeded.
    @Test("Resolver: re-run within TTL reuses manifest cache")
    func resolverCacheHitOnReRun() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-resolve-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let canonicalizer = Core.GitHubCanonicalizer(
            cacheURL: tempDir.appendingPathComponent("canonical-owners.json")
        )
        let manifestCache = Core.ManifestCache(
            rootDirectory: tempDir.appendingPathComponent("manifests")
        )

        let seeds: [PackageReference] = [
            .init(
                owner: "pointfreeco",
                repo: "swift-dependencies",
                url: "https://github.com/pointfreeco/swift-dependencies",
                priority: .ecosystem
            ),
        ]

        let resolver1 = Core.PackageDependencyResolver(
            canonicalizer: canonicalizer,
            manifestCache: manifestCache,
            concurrency: 4
        )
        let (_, firstStats) = await resolver1.resolve(seeds: seeds)
        #expect(firstStats.resolvedCount >= 1)

        // Second resolver over the same cache; both canonicalizer and manifest cache
        // are warm. Manifest cache's 24h TTL keeps entries alive.
        let resolver2 = Core.PackageDependencyResolver(
            canonicalizer: canonicalizer,
            manifestCache: manifestCache,
            concurrency: 4
        )
        let (secondPackages, secondStats) = await resolver2.resolve(seeds: seeds)
        #expect(secondStats.resolvedCount == firstStats.resolvedCount)
        #expect(secondStats.duration <= max(firstStats.duration, 1.0))
        #expect(secondPackages.count == firstStats.resolvedCount)
    }
}

@Test("Resolver: seeds that canonicalize to the same repo dedupe into one entry")
func resolverCanonicalizeDedupes() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")
    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    // Use fake repos so no real Package.swift is fetched; both canonicalize to the
    // same fake canonical name to prove dedupe.
    await canonicalizer.primeCache(
        inputOwner: "fakealias", inputRepo: "only",
        canonicalOwner: "canonicalfake", canonicalRepo: "only"
    )
    await canonicalizer.primeCache(
        inputOwner: "canonicalfake", inputRepo: "only",
        canonicalOwner: "canonicalfake", canonicalRepo: "only"
    )

    let resolver = Core.PackageDependencyResolver(canonicalizer: canonicalizer)
    let seeds: [PackageReference] = [
        .init(owner: "fakealias", repo: "only", url: "https://github.com/fakealias/only", priority: .appleOfficial),
        .init(owner: "canonicalfake", repo: "only", url: "https://github.com/canonicalfake/only", priority: .appleOfficial),
    ]
    let (packages, stats) = await resolver.resolve(seeds: seeds)
    // Repo doesn't exist → Package.swift 404 → no transitive expansion. The two
    // aliased seeds collapse to one ResolvedPackage after canonicalization.
    #expect(stats.seedCount == 1)
    let canonicalMatches = packages.filter { $0.owner == "canonicalfake" && $0.repo == "only" }
    #expect(canonicalMatches.count == 1)
    #expect(!packages.contains { $0.owner == "fakealias" })
}
