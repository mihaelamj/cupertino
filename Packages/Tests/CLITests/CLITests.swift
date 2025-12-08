@testable import CLI
import Foundation
import Testing

// MARK: - CLI Tests

/// Tests for the Cupertino CLI entry point and configuration
/// Focuses on command registration, configuration, and enum logic

// MARK: - Command Registration Tests

@Suite("CLI Command Registration")
struct CommandRegistrationTests {
    @Test("All subcommands are registered")
    func subcommandsRegistered() {
        let config = Cupertino.configuration

        #expect(config.subcommands.count == 15)
        #expect(config.subcommands.contains { $0 == SetupCommand.self })
        #expect(config.subcommands.contains { $0 == FetchCommand.self })
        #expect(config.subcommands.contains { $0 == SaveCommand.self })
        #expect(config.subcommands.contains { $0 == IndexCommand.self })
        #expect(config.subcommands.contains { $0 == ServeCommand.self })
        #expect(config.subcommands.contains { $0 == SearchCommand.self })
        #expect(config.subcommands.contains { $0 == ReadCommand.self })
        #expect(config.subcommands.contains { $0 == ListFrameworksCommand.self })
        #expect(config.subcommands.contains { $0 == ListSamplesCommand.self })
        #expect(config.subcommands.contains { $0 == SearchSamplesCommand.self })
        #expect(config.subcommands.contains { $0 == ReadSampleCommand.self })
        #expect(config.subcommands.contains { $0 == ReadSampleFileCommand.self })
        #expect(config.subcommands.contains { $0 == DoctorCommand.self })
        #expect(config.subcommands.contains { $0 == CleanupCommand.self })
        #expect(config.subcommands.contains { $0 == ReleaseCommand.self })
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
    @Test("Display names are non-empty for all types")
    func displayNamesNonEmpty() {
        let allTypes: [Cupertino.FetchType] = [
            .docs,
            .swift,
            .evolution,
            .packages,
            .packageDocs,
            .code,
            .samples,
            .archive,
            .hig,
            .all,
        ]

        for fetchType in allTypes {
            #expect(
                !fetchType.displayName.isEmpty,
                "FetchType.\(fetchType) should have a non-empty display name"
            )
        }
    }

    @Test("Output directories use home directory")
    func outputDirectoriesUseHome() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let allTypes: [Cupertino.FetchType] = [
            .docs,
            .swift,
            .evolution,
            .packages,
            .packageDocs,
            .code,
            .samples,
            .archive,
            .hig,
            .all,
        ]

        for fetchType in allTypes {
            let outputDir = fetchType.defaultOutputDir
            #expect(
                outputDir.hasPrefix(homeDir),
                "FetchType.\(fetchType) output dir should start with home directory"
            )
        }
    }

    @Test("Output directories contain base directory name")
    func outputDirectoriesContainBase() {
        let allTypes: [Cupertino.FetchType] = [
            .docs,
            .swift,
            .evolution,
            .packages,
            .packageDocs,
            .code,
            .samples,
            .archive,
            .hig,
            .all,
        ]

        for fetchType in allTypes {
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
        let directFetch = Cupertino.FetchType.directFetchTypes

        #expect(directFetch.count == 6)
        #expect(directFetch.contains(.packages))
        #expect(directFetch.contains(.packageDocs))
        #expect(directFetch.contains(.code))
        #expect(directFetch.contains(.samples))
        #expect(directFetch.contains(.archive))
        #expect(directFetch.contains(.hig))
    }

    @Test("Type categorization is mutually exclusive")
    func typeCategorization() {
        let webCrawl = Set(Cupertino.FetchType.webCrawlTypes)
        let directFetch = Set(Cupertino.FetchType.directFetchTypes)

        // Should be disjoint sets (no overlap)
        #expect(webCrawl.isDisjoint(with: directFetch))

        // All types except .all should be categorized
        let allCategorized = webCrawl.union(directFetch)
        #expect(allCategorized.count == 9) // 3 web + 6 direct
    }

    @Test("All types includes all categorized types")
    func allTypesComplete() {
        let allTypes = Cupertino.FetchType.allTypes

        #expect(allTypes.count == 9)
        #expect(allTypes.contains(.docs))
        #expect(allTypes.contains(.swift))
        #expect(allTypes.contains(.evolution))
        #expect(allTypes.contains(.packages))
        #expect(allTypes.contains(.packageDocs))
        #expect(allTypes.contains(.code))
        #expect(allTypes.contains(.samples))
        #expect(allTypes.contains(.archive))
        #expect(allTypes.contains(.hig))
    }

    @Test("Package-docs raw value has hyphen")
    func packageDocsRawValue() {
        #expect(Cupertino.FetchType.packageDocs.rawValue == "package-docs")
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
        #expect(Cupertino.FetchType.packageDocs.defaultURL.isEmpty)
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

    @Test("Packages and package-docs share base directory")
    func packagesShareDirectory() {
        let packagesDir = Cupertino.FetchType.packages.defaultOutputDir
        let packageDocsDir = Cupertino.FetchType.packageDocs.defaultOutputDir

        #expect(packagesDir == packageDocsDir, "Packages and package-docs should share the same directory")
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
