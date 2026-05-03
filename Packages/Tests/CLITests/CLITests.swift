@testable import CLI
import Foundation
import Testing

// MARK: - CLI Tests

// Tests for the Cupertino CLI entry point and configuration
// Focuses on command registration, configuration, and enum logic

// MARK: - Command Registration Tests

@Suite("CLI Command Registration")
struct CommandRegistrationTests {
    @Test("All subcommands are registered")
    func subcommandsRegistered() {
        let config = Cupertino.configuration

        // 13 visible + 1 hidden (package-search). `setup` now owns every
        // database — packages-setup was collapsed into it. `resolve-refs`
        // post-processes saved pages against #208. `index` removed in
        // #231 (samples now build via `save --samples`). `ask` absorbed
        // into `search` in #239 (default fan-out path produces the same
        // chunked output as `ask` did).
        #expect(config.subcommands.count == 14)
        #expect(config.subcommands.contains { $0 == SetupCommand.self })
        #expect(config.subcommands.contains { $0 == FetchCommand.self })
        #expect(config.subcommands.contains { $0 == SaveCommand.self })
        #expect(config.subcommands.contains { $0 == ServeCommand.self })
        #expect(config.subcommands.contains { $0 == SearchCommand.self })
        #expect(config.subcommands.contains { $0 == ReadCommand.self })
        #expect(config.subcommands.contains { $0 == ListFrameworksCommand.self })
        #expect(config.subcommands.contains { $0 == ListSamplesCommand.self })
        #expect(config.subcommands.contains { $0 == ReadSampleCommand.self })
        #expect(config.subcommands.contains { $0 == ReadSampleFileCommand.self })
        #expect(config.subcommands.contains { $0 == DoctorCommand.self })
        #expect(config.subcommands.contains { $0 == CleanupCommand.self })
        #expect(config.subcommands.contains { $0 == PackageSearchCommand.self })
        #expect(config.subcommands.contains { $0 == ResolveRefsCommand.self })
    }

    @Test("Default subcommand is ServeCommand")
    func defaultSubcommand() {
        let config = Cupertino.configuration
        #expect(config.defaultSubcommand == ServeCommand.self)
    }

    @Test("Command name is set correctly")
    func commandName() {
        let config = Cupertino.configuration
        #expect(config.commandName == "cupertino")
    }

    @Test("Version string is not empty")
    func versionNotEmpty() {
        let config = Cupertino.configuration
        #expect(!config.version.isEmpty)
    }

    @Test("Abstract description exists")
    func abstractExists() {
        let config = Cupertino.configuration
        #expect(!config.abstract.isEmpty)
        #expect(config.abstract.contains("MCP"))
    }
}

// MARK: - FetchType Enum Tests

@Suite("FetchType Enum")
struct FetchTypeTests {
    /// After #217, .packageDocs was merged into .packages — there is no
    /// separate "package-docs" fetch type any more.
    private static let allTypes: [Cupertino.FetchType] = [
        .docs,
        .swift,
        .evolution,
        .packages,
        .code,
        .samples,
        .archive,
        .hig,
        .all,
    ]

    @Test("Display names are non-empty for all types")
    func displayNamesNonEmpty() {
        for fetchType in Self.allTypes {
            #expect(
                !fetchType.displayName.isEmpty,
                "FetchType.\(fetchType) should have a non-empty display name"
            )
        }
    }

    @Test("Output directories use home directory")
    func outputDirectoriesUseHome() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        for fetchType in Self.allTypes {
            let outputDir = fetchType.defaultOutputDir
            #expect(
                outputDir.hasPrefix(homeDir),
                "FetchType.\(fetchType) output dir should start with home directory"
            )
        }
    }

    @Test("Output directories contain base directory name")
    func outputDirectoriesContainBase() {
        for fetchType in Self.allTypes {
            let outputDir = fetchType.defaultOutputDir
            #expect(
                outputDir.contains("cupertino"),
                "FetchType.\(fetchType) output dir should contain 'cupertino'"
            )
        }
    }

    @Test("Web crawl types are correctly categorized")
    func webCrawlTypes() {
        let webCrawl = Cupertino.FetchType.webCrawlTypes

        #expect(webCrawl.count == 3)
        #expect(webCrawl.contains(.docs))
        #expect(webCrawl.contains(.swift))
        #expect(webCrawl.contains(.evolution))
    }

    @Test("Direct fetch types are correctly categorized")
    func directFetchTypes() {
        // After #217: .packages now does both metadata + archives, so the
        // separate .packageDocs case is gone. directFetch went from 7 → 6.
        let directFetch = Cupertino.FetchType.directFetchTypes

        #expect(directFetch.count == 6)
        #expect(directFetch.contains(.packages))
        #expect(directFetch.contains(.code))
        #expect(directFetch.contains(.samples))
        #expect(directFetch.contains(.archive))
        #expect(directFetch.contains(.hig))
        #expect(directFetch.contains(.availability))
    }

    @Test("Type categorization is mutually exclusive")
    func typeCategorization() {
        let webCrawl = Set(Cupertino.FetchType.webCrawlTypes)
        let directFetch = Set(Cupertino.FetchType.directFetchTypes)

        // Should be disjoint sets (no overlap)
        #expect(webCrawl.isDisjoint(with: directFetch))

        // All types except .all should be categorized
        let allCategorized = webCrawl.union(directFetch)
        #expect(allCategorized.count == 9) // 3 web + 6 direct (#217 dropped .packageDocs)
    }

    @Test("All types includes all categorized types")
    func allTypesComplete() {
        let allTypes = Cupertino.FetchType.allTypes

        #expect(allTypes.count == 9)
        #expect(allTypes.contains(.docs))
        #expect(allTypes.contains(.swift))
        #expect(allTypes.contains(.evolution))
        #expect(allTypes.contains(.packages))
        #expect(allTypes.contains(.code))
        #expect(allTypes.contains(.samples))
        #expect(allTypes.contains(.archive))
        #expect(allTypes.contains(.hig))
        #expect(allTypes.contains(.availability))
    }

    @Test("Raw values match expected CLI arguments")
    func rawValuesMatchCLI() {
        #expect(Cupertino.FetchType.docs.rawValue == "docs")
        #expect(Cupertino.FetchType.swift.rawValue == "swift")
        #expect(Cupertino.FetchType.evolution.rawValue == "evolution")
        #expect(Cupertino.FetchType.packages.rawValue == "packages")
        #expect(Cupertino.FetchType.code.rawValue == "code")
        #expect(Cupertino.FetchType.all.rawValue == "all")
    }

    @Test("Default URLs are set for web crawl types")
    func defaultURLsForWebCrawl() {
        #expect(!Cupertino.FetchType.docs.defaultURL.isEmpty)
        #expect(!Cupertino.FetchType.swift.defaultURL.isEmpty)
        #expect(Cupertino.FetchType.docs.defaultURL.hasPrefix("https://"))
        #expect(Cupertino.FetchType.swift.defaultURL.hasPrefix("https://"))
    }

    @Test("Default URLs are empty for non-web types")
    func defaultURLsEmptyForNonWeb() {
        // These types use different fetching mechanisms
        #expect(Cupertino.FetchType.evolution.defaultURL.isEmpty)
        #expect(Cupertino.FetchType.packages.defaultURL.isEmpty)
        #expect(Cupertino.FetchType.code.defaultURL.isEmpty)
        #expect(Cupertino.FetchType.all.defaultURL.isEmpty)
    }

    @Test("Output directories are unique per type")
    func uniqueOutputDirectories() {
        let types: [Cupertino.FetchType] = [
            .docs,
            .swift,
            .evolution,
            .packages,
            .code,
        ]

        let directories = Set(types.map(\.defaultOutputDir))
        #expect(directories.count == types.count, "Each type should have a unique output directory")
    }

    @Test("packages display name surfaces the merged scope (#217)")
    func packagesDisplayName() {
        // Display name should mention "Package" so the user knows what's
        // being fetched; specifics (metadata + archives) are in --help.
        #expect(Cupertino.FetchType.packages.displayName.contains("Package"))
    }
}

// MARK: - FetchType Display Name Tests

@Suite("FetchType Display Names")
struct FetchTypeDisplayNameTests {
    @Test("Display names are user-friendly")
    func displayNamesUserFriendly() {
        // Display names should be properly formatted for user output
        #expect(Cupertino.FetchType.docs.displayName.contains("Apple"))
        #expect(Cupertino.FetchType.swift.displayName.contains("Swift"))
        #expect(Cupertino.FetchType.evolution.displayName.contains("Evolution"))
        #expect(Cupertino.FetchType.packages.displayName.contains("Package"))
        #expect(Cupertino.FetchType.code.displayName.contains("Sample"))
    }

    @Test("Display names are consistent with purpose")
    func displayNamesConsistent() {
        let docsName = Cupertino.FetchType.docs.displayName
        let swiftName = Cupertino.FetchType.swift.displayName

        // Should clearly distinguish between different doc types
        #expect(docsName != swiftName)
    }
}

// MARK: - SaveCommand preflight (#232)

@Suite("SaveCommand.preflightLines (#232)")
struct SaveCommandPreflightTests {
    @Test("Empty base dir → all three scopes report missing")
    func emptyBaseAllMissing() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lines = SaveCommand.preflightLines(
            buildDocs: true,
            buildPackages: true,
            buildSamples: true,
            baseDir: dir.path,
            docsDir: nil,
            samplesDir: dir.appendingPathComponent("sample-code").path
        )

        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("Docs (search.db)"))
        #expect(joined.contains("Packages (packages.db)"))
        #expect(joined.contains("Samples (samples.db)"))
        #expect(joined.contains("missing"))
    }

    @Test("Skipped scopes don't appear in output")
    func skippedScopesAbsent() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lines = SaveCommand.preflightLines(
            buildDocs: false,
            buildPackages: true,
            buildSamples: false,
            baseDir: dir.path,
            docsDir: nil,
            samplesDir: nil
        )

        let joined = lines.joined(separator: "\n")
        #expect(!joined.contains("Docs (search.db)"))
        #expect(joined.contains("Packages (packages.db)"))
        #expect(!joined.contains("Samples (samples.db)"))
    }

    @Test("Packages dir with sidecars reports full coverage")
    func packagesWithSidecars() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create packages/owner/repo/availability.json
        let pkgRoot = dir.appendingPathComponent("packages/apple/swift-nio")
        try FileManager.default.createDirectory(at: pkgRoot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pkgRoot.appendingPathComponent("availability.json"))

        let lines = SaveCommand.preflightLines(
            buildDocs: false,
            buildPackages: true,
            buildSamples: false,
            baseDir: dir.path
        )
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("(1 packages)"))
        #expect(joined.contains("(1/1)"))
    }

    @Test("Packages dir without sidecars flags missing annotations")
    func packagesWithoutSidecars() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pkgRoot = dir.appendingPathComponent("packages/apple/swift-nio")
        try FileManager.default.createDirectory(at: pkgRoot, withIntermediateDirectories: true)
        // No availability.json

        let lines = SaveCommand.preflightLines(
            buildDocs: false,
            buildPackages: true,
            buildSamples: false,
            baseDir: dir.path
        )
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("(0/1)"))
        #expect(joined.contains("backfill"))
    }

    @Test("countPackagesAndSidecars correctly counts owner/repo dirs")
    func countPackagesAndSidecars() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        for (owner, repo, hasSidecar) in [
            ("apple", "swift-nio", true),
            ("apple", "swift-collections", false),
            ("vapor", "vapor", true),
        ] {
            let pkg = dir.appendingPathComponent("\(owner)/\(repo)")
            try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
            if hasSidecar {
                try Data("{}".utf8).write(to: pkg.appendingPathComponent("availability.json"))
            }
        }

        let stats = SaveCommand.countPackagesAndSidecars(at: dir)
        #expect(stats.packages == 3)
        #expect(stats.sidecars == 2)
    }

    @Test("checkDocsHaveAvailability returns false on empty docs dir")
    func checkDocsAvailabilityEmpty() throws {
        let dir = try Self.makeEmptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SaveCommand.checkDocsHaveAvailability(docsDir: dir) == false)
    }

    private static func makeEmptyTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-preflight-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
