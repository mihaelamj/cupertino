@testable import CLI
import Foundation
import SharedConstants
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
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Setup.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Fetch.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Save.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Serve.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Search.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Read.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ListFrameworks.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ListSamples.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ReadSample.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ReadSampleFile.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Doctor.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Cleanup.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.PackageSearch.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ResolveRefs.self })
    }

    @Test("Default subcommand is CLIImpl.Command.Serve")
    func defaultSubcommand() {
        let config = Cupertino.configuration
        #expect(config.defaultSubcommand == CLIImpl.Command.Serve.self)
    }

    @Test("Command name is set correctly")
    func commandName() {
        let config = Cupertino.configuration
        #expect(config.commandName == "cupertino")
    }

    @Test("Release.Version string is not empty")
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
        // Path-DI migration (#535): pass a stub `Shared.Paths` rooted under the
        // current user's home directory so the assertion still has something
        // to compare against.
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let stubPaths = Shared.Paths(baseDirectory: URL(fileURLWithPath: homeDir).appendingPathComponent(".cupertino"))
        for fetchType in Self.allTypes {
            let outputDir = fetchType.defaultOutputDir(paths: stubPaths)
            #expect(
                outputDir.hasPrefix(homeDir),
                "FetchType.\(fetchType) output dir should start with home directory"
            )
        }
    }

    @Test("Output directories contain base directory name")
    func outputDirectoriesContainBase() {
        // Path-DI migration (#535): see uniqueOutputDirectories for the rationale.
        let stubPaths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/.cupertino"))
        for fetchType in Self.allTypes {
            let outputDir = fetchType.defaultOutputDir(paths: stubPaths)
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

        // Path-DI migration (#535): defaultOutputDir takes a `Shared.Paths` injection,
        // so it's a method now rather than a computed property — pass a stub.
        let stubPaths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/cupertino-test-stub"))
        let directories = Set(types.map { $0.defaultOutputDir(paths: stubPaths) })
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

// SaveCommandPreflightTests was moved to Tests/IndexerTests/PreflightTests.swift
// in #244. The preflight pipeline now lives in `Indexer.Preflight`.

// MARK: - Cupertino.Composition Mediator (#548 Phase B)

@Suite("Cupertino.Composition")
struct CupertinoCompositionTests {
    @Test("Composition() builds a coherent logging + paths graph")
    func compositionBuildsCoherentGraph() {
        // The Mediator owns both deps; both fields must be non-nil-equivalent
        // and the recording must trace back to the same Unified actor the
        // composition holds. This pins the Abstract Factory wiring.
        let composition = Cupertino.Composition()
        // `paths.baseDirectory` is required for Shared.Paths to derive any
        // of its 13 derived URLs; the constructor would have crashed if the
        // value couldn't resolve, so simply reaching it confirms wiring.
        _ = composition.paths.baseDirectory
        _ = composition.logging.recording
    }

    @Test("Composition init accepts overrides for both deps (test seam)")
    func compositionAcceptsOverrides() {
        // Tests that need a stub logger / custom paths build their own
        // Logging.Composition and Shared.Paths and inject them. This is
        // the entry point a future Cupertino integration-test runner
        // uses to feed the @TaskLocal a fake binary world.
        let stubPaths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/cupertino-composition-test"))
        let composition = Cupertino.Composition(paths: stubPaths)
        #expect(composition.paths.baseDirectory.path == "/tmp/cupertino-composition-test")
    }

    @Test("Cupertino.Context.composition has a default value before main() binds one")
    func contextDefaultIsReachable() {
        // The @TaskLocal default exists so unit tests that touch a command
        // body without going through Cupertino.main() still get a reachable
        // composition. Reading it without crashing is the contract.
        let composition = Cupertino.Context.composition
        _ = composition.paths.baseDirectory
        _ = composition.logging.recording
    }

    @Test("Cupertino.Context.$composition.withValue overrides the binding for its scope")
    func contextWithValueScoping() {
        // Verify the SE-0311 binding behaviour: within `withValue { … }`,
        // the override is visible; outside, the previous (default) value
        // returns. This is the contract Cupertino.main() relies on.
        //
        // Both the closure body and `TaskLocal.withValue` resolve to the
        // synchronous overload here (no `await` in the closure body), so
        // the test function is non-async and the call site doesn't carry
        // `await`. The earlier shape emitted a Swift Testing warning
        // ("await on non-async expression") because the compiler had
        // selected the sync overload.
        let stubPaths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/cupertino-withvalue-test"))
        let scoped = Cupertino.Composition(paths: stubPaths)
        Cupertino.Context.$composition.withValue(scoped) {
            #expect(Cupertino.Context.composition.paths.baseDirectory.path == "/tmp/cupertino-withvalue-test")
        }
        // Outside the scope, the default-built composition's baseDirectory
        // is NOT the stub path — confirms the binding properly cleared.
        #expect(Cupertino.Context.composition.paths.baseDirectory.path != "/tmp/cupertino-withvalue-test")
    }
}
