import ArgumentParser
@testable import CLI
import Foundation
import SharedConstants
import Testing

// MARK: - #1158: per-command option-parity surface tests

/// SURFACE-depth parity coverage for every cupertino subcommand and every
/// one of its options, at the same depth the MCP tools are tested
/// (registration + the parameter surface). Two kinds of assertion:
///
/// 1. Registration: every subcommand type listed in the root command's
///    `subcommands` array is present, and the count is pinned so a future
///    drop is caught.
/// 2. Per-option parse-binding: for each command, parsing a representative
///    argv that sets every option binds each property to the supplied
///    sentinel value (flags toggle to their non-default), and a removed /
///    unknown flag is rejected where #1157 retired one.
///
/// This is parse-binding + registration only. Behavioral / DB / output
/// coverage lives elsewhere (e.g. `Issue1154MultiDBFanOutTests`,
/// `OutputFormatAliasTests`). The pattern mirrors those files:
/// `try CLIImpl.Command.X.parse([...])` then `#expect` on the parsed
/// property; do/catch for "old flag rejected".
@Suite("#1158: command + option parse-binding parity")
struct Issue1158CommandOptionParityTests {
    // MARK: - Registration

    /// The complete set of subcommand types the root command must register.
    /// Source of truth is `Cupertino.configuration.subcommands`; this is the
    /// expectation list the test compares it against by type identity.
    private static let expectedSubcommands: [any ParsableCommand.Type] = [
        CLIImpl.Command.Setup.self,
        CLIImpl.Command.Fetch.self,
        CLIImpl.Command.Save.self,
        CLIImpl.Command.Serve.self,
        CLIImpl.Command.Search.self,
        CLIImpl.Command.Read.self,
        CLIImpl.Command.ListFrameworks.self,
        CLIImpl.Command.ListDocuments.self,
        CLIImpl.Command.ListChildren.self,
        CLIImpl.Command.ListSources.self,
        CLIImpl.Command.ListSamples.self,
        CLIImpl.Command.ReadSample.self,
        CLIImpl.Command.ReadSampleFile.self,
        CLIImpl.Command.Doctor.self,
        CLIImpl.Command.Cleanup.self,
        CLIImpl.Command.PackageSearch.self,
        CLIImpl.Command.ResolveRefs.self,
        CLIImpl.Command.Inheritance.self,
        CLIImpl.Command.SearchSymbols.self,
        CLIImpl.Command.SearchPropertyWrappers.self,
        CLIImpl.Command.SearchConcurrency.self,
        CLIImpl.Command.SearchConformances.self,
        CLIImpl.Command.SearchGenerics.self,
    ]

    @Test("root command registers every subcommand exactly once")
    func everySubcommandIsRegistered() {
        let registered = Set(Cupertino.configuration.subcommands.map(ObjectIdentifier.init))

        // Count pin: a future add / drop that doesn't update both the root
        // array and this expectation list trips here.
        #expect(
            Cupertino.configuration.subcommands.count == Self.expectedSubcommands.count,
            "root subcommand count drifted: root=\(Cupertino.configuration.subcommands.count) expected=\(Self.expectedSubcommands.count)"
        )

        for type in Self.expectedSubcommands {
            #expect(
                registered.contains(ObjectIdentifier(type)),
                "subcommand \(type) is not registered in the root command's subcommands array"
            )
        }

        // The default subcommand is `serve` (no-subcommand invocation starts
        // the MCP server). Pin it so a reorder / drop is caught.
        let defaultSubcommand = Cupertino.configuration.defaultSubcommand
        #expect(defaultSubcommand != nil, "root command must declare a defaultSubcommand")
        if let defaultSubcommand {
            #expect(
                ObjectIdentifier(defaultSubcommand) == ObjectIdentifier(CLIImpl.Command.Serve.self),
                "defaultSubcommand must be Serve"
            )
        }
    }

    // MARK: - setup

    @Test("setup: every option parses + binds")
    func setupOptions() throws {
        let cmd = try CLIImpl.Command.Setup.parse([
            "--base-dir", "/tmp/setup-base",
            "--keep-existing",
        ])
        #expect(cmd.baseDir == "/tmp/setup-base")
        #expect(cmd.keepExisting == true)
    }

    // MARK: - fetch

    @Test("fetch: every option parses + binds")
    func fetchOptions() throws {
        let cmd = try CLIImpl.Command.Fetch.parse([
            "--source", "swift-evolution",
            "--start-url", "https://example.com/start",
            "--max-pages", "42",
            "--max-depth", "7",
            "--request-delay", "0.25",
            "--output-dir", "/tmp/fetch-out",
            "--allowed-prefixes", "https://a.com,https://b.com",
            "--force",
            "--start-clean",
            "--retry-errors",
            "--baseline", "/tmp/baseline",
            "--urls", "/tmp/urls.txt",
            "--discovery-mode", "json-only",
            "--no-only-accepted",
            "--limit", "9",
            "--fast",
            "--no-recurse",
            "--refresh",
            "--refresh-metadata",
            "--skip-archives",
            "--annotate-availability",
        ])
        #expect(cmd.source == "swift-evolution")
        #expect(cmd.startURL == "https://example.com/start")
        #expect(cmd.maxPages == 42)
        #expect(cmd.maxDepth == 7)
        #expect(cmd.requestDelay == 0.25)
        #expect(cmd.outputDir == "/tmp/fetch-out")
        #expect(cmd.allowedPrefixes == "https://a.com,https://b.com")
        #expect(cmd.force == true)
        #expect(cmd.startClean == true)
        #expect(cmd.retryErrors == true)
        #expect(cmd.baseline == "/tmp/baseline")
        #expect(cmd.urls == "/tmp/urls.txt")
        #expect(cmd.discoveryMode == .jsonOnly)
        // `--only-accepted` defaults to true; `--no-only-accepted` toggles it off.
        #expect(cmd.onlyAccepted == false)
        #expect(cmd.limit == 9)
        #expect(cmd.fast == true)
        // `--recurse` defaults to true; `--no-recurse` toggles it off.
        #expect(cmd.recurse == false)
        #expect(cmd.refresh == true)
        #expect(cmd.refreshMetadata == true)
        #expect(cmd.skipArchives == true)
        #expect(cmd.annotateAvailability == true)
    }

    // MARK: - save

    @Test("save: every option parses + binds")
    func saveOptions() throws {
        let cmd = try CLIImpl.Command.Save.parse([
            "--base-dir", "/tmp/save-base",
            "--docs-dir", "/tmp/docs",
            "--evolution-dir", "/tmp/evo",
            "--swift-org-dir", "/tmp/sworg",
            "--packages-dir", "/tmp/pkgs",
            "--archive-dir", "/tmp/arch",
            "--hig-dir", "/tmp/hig",
            "--swift-book-dir", "/tmp/book",
            "--metadata-file", "/tmp/meta.json",
            "--clear",
            "--allow-degraded-enrichment",
            "--remote",
            "--source", "apple-docs",
            "--source", "hig",
            "--all",
            "--samples-dir", "/tmp/samples",
            "--samples-db", "/tmp/samples.db",
            "--force",
            "--yes",
            "--dry-run",
            "--force-replace",
            "--force-replace-grace", "60",
        ])
        #expect(cmd.baseDir == "/tmp/save-base")
        #expect(cmd.docsDir == "/tmp/docs")
        #expect(cmd.evolutionDir == "/tmp/evo")
        #expect(cmd.swiftOrgDir == "/tmp/sworg")
        #expect(cmd.packagesDir == "/tmp/pkgs")
        #expect(cmd.archiveDir == "/tmp/arch")
        #expect(cmd.higDir == "/tmp/hig")
        #expect(cmd.swiftBookDir == "/tmp/book")
        #expect(cmd.metadataFile == "/tmp/meta.json")
        #expect(cmd.clear == true)
        #expect(cmd.allowDegradedEnrichment == true)
        #expect(cmd.remote == true)
        #expect(cmd.source == ["apple-docs", "hig"])
        #expect(cmd.all == true)
        #expect(cmd.samplesDir == "/tmp/samples")
        #expect(cmd.samplesDB == "/tmp/samples.db")
        #expect(cmd.force == true)
        #expect(cmd.yes == true)
        #expect(cmd.dryRun == true)
        #expect(cmd.forceReplace == true)
        #expect(cmd.forceReplaceGrace == 60)
    }

    @Test("save: -y short flag binds yes")
    func saveYesShortFlag() throws {
        let cmd = try CLIImpl.Command.Save.parse(["--all", "-y"])
        #expect(cmd.yes == true)
    }

    // MARK: - serve

    @Test("serve: every option parses + binds")
    func serveOptions() throws {
        let cmd = try CLIImpl.Command.Serve.parse(["--no-reap"])
        #expect(cmd.noReap == true)

        // Default: reaper stays on.
        let defaultCmd = try CLIImpl.Command.Serve.parse([])
        #expect(defaultCmd.noReap == false)
    }

    // MARK: - search

    @Test("search: every option parses + binds")
    func searchOptions() throws {
        let cmd = try CLIImpl.Command.Search.parse([
            "the search query",
            "--source", "apple-docs",
            "--include-archive",
            "--framework", "swiftui",
            "--language", "swift",
            "--limit", "11",
            "--min-ios", "17.0",
            "--min-macos", "14.0",
            "--min-tvos", "17.0",
            "--min-watchos", "10.0",
            "--min-visionos", "1.0",
            "--swift", "6.0",
            "--apple-imports", "Combine",
            "--packages-db", "/tmp/packages.db",
            "--sample-db", "/tmp/sample.db",
            "--per-source", "4",
            "--skip-docs",
            "--skip-packages",
            "--skip-samples",
            "--brief",
            "--platform", "iOS",
            "--min-version", "16.0",
            "--format", "json",
        ])
        #expect(cmd.query == "the search query")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.includeArchive == true)
        #expect(cmd.framework == "swiftui")
        #expect(cmd.language == "swift")
        #expect(cmd.limit == 11)
        #expect(cmd.minIos == "17.0")
        #expect(cmd.minMacos == "14.0")
        #expect(cmd.minTvos == "17.0")
        #expect(cmd.minWatchos == "10.0")
        #expect(cmd.minVisionos == "1.0")
        #expect(cmd.swift == "6.0")
        #expect(cmd.appleImports == "Combine")
        #expect(cmd.packagesDb == "/tmp/packages.db")
        #expect(cmd.sampleDb == "/tmp/sample.db")
        #expect(cmd.perSource == 4)
        #expect(cmd.skipDocs == true)
        #expect(cmd.skipPackages == true)
        #expect(cmd.skipSamples == true)
        #expect(cmd.brief == true)
        #expect(cmd.platform == "iOS")
        #expect(cmd.minVersion == "16.0")
        #expect(cmd.format == .json)
    }

    @Test("search: short flags bind source / framework / language")
    func searchShortFlags() throws {
        let cmd = try CLIImpl.Command.Search.parse([
            "q",
            "-s", "samples",
            "-f", "uikit",
            "-l", "objc",
        ])
        #expect(cmd.source == "samples")
        #expect(cmd.framework == "uikit")
        #expect(cmd.language == "objc")
    }

    @Test("search: format alias `md` binds markdown")
    func searchFormatMarkdownAlias() throws {
        let cmd = try CLIImpl.Command.Search.parse(["q", "--format", "md"])
        #expect(cmd.format == .markdown)
    }

    // MARK: - read

    @Test("read: every option parses + binds")
    func readOptions() throws {
        let cmd = try CLIImpl.Command.Read.parse([
            "apple-docs://swiftui/documentation_swiftui_view",
            "--source", "apple-docs",
            "--format", "markdown",
            "--sample-db", "/tmp/sample.db",
            "--packages-db", "/tmp/packages.db",
        ])
        #expect(cmd.identifier == "apple-docs://swiftui/documentation_swiftui_view")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.format == .markdown)
        #expect(cmd.sampleDb == "/tmp/sample.db")
        #expect(cmd.packagesDb == "/tmp/packages.db")
    }

    // MARK: - list-frameworks

    @Test("list-frameworks: every option parses + binds")
    func listFrameworksOptions() throws {
        let cmd = try CLIImpl.Command.ListFrameworks.parse([
            "--format", "json",
        ])
        #expect(cmd.format == .json)
    }

    // MARK: - list-documents

    @Test("list-documents: every option parses + binds")
    func listDocumentsOptions() throws {
        let cmd = try CLIImpl.Command.ListDocuments.parse([
            "--framework", "swiftui",
            "--source", "apple-docs",
            "--offset", "25",
            "--limit", "125",
            "--format", "json",
        ])
        #expect(cmd.framework == "swiftui")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.offset == 25)
        #expect(cmd.limit == 125)
        #expect(cmd.format == .json)
    }

    // MARK: - list-children

    @Test("list-children: every option parses + binds")
    func listChildrenOptions() throws {
        let cmd = try CLIImpl.Command.ListChildren.parse([
            "apple-docs://swiftui#Essentials",
            "--source", "apple-docs",
            "--format", "json",
        ])
        #expect(cmd.uri == "apple-docs://swiftui#Essentials")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.format == .json)
    }

    // MARK: - list-samples

    @Test("list-samples: every option parses + binds")
    func listSamplesOptions() throws {
        let cmd = try CLIImpl.Command.ListSamples.parse([
            "--framework", "swiftui",
            "--limit", "33",
            "--format", "json",
            "--sample-db", "/tmp/sample.db",
        ])
        #expect(cmd.framework == "swiftui")
        #expect(cmd.limit == 33)
        #expect(cmd.format == .json)
        #expect(cmd.sampleDb == "/tmp/sample.db")

        // `-f` is the short alias for `--framework`.
        let shortCmd = try CLIImpl.Command.ListSamples.parse(["-f", "uikit"])
        #expect(shortCmd.framework == "uikit")
    }

    // MARK: - read-sample

    @Test("read-sample: every option parses + binds")
    func readSampleOptions() throws {
        let cmd = try CLIImpl.Command.ReadSample.parse([
            "building-a-document-based-app-with-swiftui",
            "--format", "json",
            "--sample-db", "/tmp/sample.db",
        ])
        #expect(cmd.projectId == "building-a-document-based-app-with-swiftui")
        #expect(cmd.format == .json)
        #expect(cmd.sampleDb == "/tmp/sample.db")
    }

    // MARK: - read-sample-file

    @Test("read-sample-file: every option parses + binds")
    func readSampleFileOptions() throws {
        let cmd = try CLIImpl.Command.ReadSampleFile.parse([
            "building-a-document-based-app-with-swiftui",
            "ContentView.swift",
            "--format", "json",
            "--sample-db", "/tmp/sample.db",
        ])
        #expect(cmd.projectId == "building-a-document-based-app-with-swiftui")
        #expect(cmd.filePath == "ContentView.swift")
        #expect(cmd.format == .json)
        #expect(cmd.sampleDb == "/tmp/sample.db")
    }

    // MARK: - doctor

    @Test("doctor: every option parses + binds")
    func doctorOptions() throws {
        // #1209 removed the partial `--docs-dir` / `--evolution-dir` overrides
        // from doctor; the corpus-directory check now resolves every source's
        // directory uniformly from the registry default.
        let cmd = try CLIImpl.Command.Doctor.parse([
            "--save",
            "--kind-coverage",
            "--freshness",
        ])
        #expect(cmd.save == true)
        #expect(cmd.kindCoverage == true)
        #expect(cmd.freshness == true)
    }

    // MARK: - cleanup

    @Test("cleanup: every option parses + binds")
    func cleanupOptions() throws {
        let cmd = try CLIImpl.Command.Cleanup.parse([
            "--sample-code-dir", "/tmp/sample-code",
            "--dry-run",
            "--keep-originals",
            "--verify",
        ])
        #expect(cmd.sampleCodeDir == "/tmp/sample-code")
        #expect(cmd.dryRun == true)
        #expect(cmd.keepOriginals == true)
        #expect(cmd.verify == true)
    }

    // MARK: - package-search

    @Test("package-search: every option parses + binds")
    func packageSearchOptions() throws {
        let cmd = try CLIImpl.Command.PackageSearch.parse([
            "how do I write a log handler in swift-log",
            "--limit", "5",
            "--db", "/tmp/packages.db",
            "--platform", "macOS",
            "--min-version", "13.0",
            "--swift-tools", "5.9",
        ])
        #expect(cmd.question == "how do I write a log handler in swift-log")
        #expect(cmd.limit == 5)
        #expect(cmd.db == "/tmp/packages.db")
        #expect(cmd.platform == "macOS")
        #expect(cmd.minVersion == "13.0")
        #expect(cmd.swiftTools == "5.9")
    }

    // MARK: - resolve-refs

    @Test("resolve-refs: every option parses + binds")
    func resolveRefsOptions() throws {
        let cmd = try CLIImpl.Command.ResolveRefs.parse([
            "--input", "/tmp/_docs",
            "--use-network",
            "--use-webview",
            "--print-unresolved",
        ])
        #expect(cmd.input == "/tmp/_docs")
        #expect(cmd.useNetwork == true)
        #expect(cmd.useWebview == true)
        #expect(cmd.printUnresolved == true)
    }

    // MARK: - inheritance

    @Test("inheritance: every option parses + binds")
    func inheritanceOptions() throws {
        let cmd = try CLIImpl.Command.Inheritance.parse([
            "UIButton",
            "--direction", "down",
            "--depth", "3",
            "--format", "json",
            "--framework", "uikit",
        ])
        #expect(cmd.symbol == "UIButton")
        #expect(cmd.direction == .down)
        #expect(cmd.depth == 3)
        #expect(cmd.format == .json)
        #expect(cmd.framework == "uikit")
    }

    // MARK: - search-symbols (AST)

    @Test("search-symbols: every option parses + binds")
    func searchSymbolsOptions() throws {
        let cmd = try CLIImpl.Command.SearchSymbols.parse([
            "--query", "Task",
            "--kind", "struct",
            "--is-async",
            "--framework", "swiftui",
            "--limit", "15",
            "--format", "json",
            "--base-dir", "/tmp/base",
            "--source", "apple-docs",
            "--min-ios", "17.0",
            "--min-macos", "14.0",
            "--min-tvos", "17.0",
            "--min-watchos", "10.0",
            "--min-visionos", "1.0",
        ])
        #expect(cmd.query == "Task")
        #expect(cmd.kind == "struct")
        #expect(cmd.isAsync == true)
        #expect(cmd.framework == "swiftui")
        #expect(cmd.limit == 15)
        #expect(cmd.format == .json)
        #expect(cmd.baseDir == "/tmp/base")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.platformFloors.minIos == "17.0")
        #expect(cmd.platformFloors.minMacos == "14.0")
        #expect(cmd.platformFloors.minTvos == "17.0")
        #expect(cmd.platformFloors.minWatchos == "10.0")
        #expect(cmd.platformFloors.minVisionos == "1.0")
    }

    @Test("search-symbols: retired --search-db flag is rejected (#1157)")
    func searchSymbolsRejectsSearchDB() throws {
        var threw = false
        do {
            _ = try CLIImpl.Command.SearchSymbols.parse(["--query", "Task", "--search-db", "/tmp/x"])
        } catch {
            threw = true
        }
        #expect(threw, "search-symbols must reject the retired --search-db flag")
    }

    // MARK: - search-property-wrappers (AST)

    @Test("search-property-wrappers: every option parses + binds")
    func searchPropertyWrappersOptions() throws {
        let cmd = try CLIImpl.Command.SearchPropertyWrappers.parse([
            "--wrapper", "State",
            "--framework", "swiftui",
            "--limit", "8",
            "--format", "json",
            "--base-dir", "/tmp/base",
            "--source", "apple-docs",
            "--min-ios", "17.0",
            "--min-macos", "14.0",
            "--min-tvos", "17.0",
            "--min-watchos", "10.0",
            "--min-visionos", "1.0",
        ])
        #expect(cmd.wrapper == "State")
        #expect(cmd.framework == "swiftui")
        #expect(cmd.limit == 8)
        #expect(cmd.format == .json)
        #expect(cmd.baseDir == "/tmp/base")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.platformFloors.minIos == "17.0")
        #expect(cmd.platformFloors.minMacos == "14.0")
        #expect(cmd.platformFloors.minTvos == "17.0")
        #expect(cmd.platformFloors.minWatchos == "10.0")
        #expect(cmd.platformFloors.minVisionos == "1.0")
    }

    @Test("search-property-wrappers: retired --search-db flag is rejected (#1157)")
    func searchPropertyWrappersRejectsSearchDB() throws {
        var threw = false
        do {
            _ = try CLIImpl.Command.SearchPropertyWrappers.parse(["--wrapper", "State", "--search-db", "/tmp/x"])
        } catch {
            threw = true
        }
        #expect(threw, "search-property-wrappers must reject the retired --search-db flag")
    }

    // MARK: - search-concurrency (AST)

    @Test("search-concurrency: every option parses + binds")
    func searchConcurrencyOptions() throws {
        let cmd = try CLIImpl.Command.SearchConcurrency.parse([
            "--pattern", "async",
            "--framework", "swiftui",
            "--limit", "12",
            "--format", "json",
            "--base-dir", "/tmp/base",
            "--source", "apple-docs",
            "--min-ios", "17.0",
            "--min-macos", "14.0",
            "--min-tvos", "17.0",
            "--min-watchos", "10.0",
            "--min-visionos", "1.0",
        ])
        #expect(cmd.pattern == "async")
        #expect(cmd.framework == "swiftui")
        #expect(cmd.limit == 12)
        #expect(cmd.format == .json)
        #expect(cmd.baseDir == "/tmp/base")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.platformFloors.minIos == "17.0")
        #expect(cmd.platformFloors.minMacos == "14.0")
        #expect(cmd.platformFloors.minTvos == "17.0")
        #expect(cmd.platformFloors.minWatchos == "10.0")
        #expect(cmd.platformFloors.minVisionos == "1.0")
    }

    @Test("search-concurrency: retired --search-db flag is rejected (#1157)")
    func searchConcurrencyRejectsSearchDB() throws {
        var threw = false
        do {
            _ = try CLIImpl.Command.SearchConcurrency.parse(["--pattern", "async", "--search-db", "/tmp/x"])
        } catch {
            threw = true
        }
        #expect(threw, "search-concurrency must reject the retired --search-db flag")
    }

    // MARK: - search-conformances (AST)

    @Test("search-conformances: every option parses + binds")
    func searchConformancesOptions() throws {
        let cmd = try CLIImpl.Command.SearchConformances.parse([
            "--protocol", "View",
            "--framework", "swiftui",
            "--limit", "6",
            "--format", "json",
            "--base-dir", "/tmp/base",
            "--source", "apple-docs",
            "--min-ios", "17.0",
            "--min-macos", "14.0",
            "--min-tvos", "17.0",
            "--min-watchos", "10.0",
            "--min-visionos", "1.0",
        ])
        // `--protocol` is bound to `protocolName` via `.customLong("protocol")`
        // because `protocol` is a Swift reserved keyword.
        #expect(cmd.protocolName == "View")
        #expect(cmd.framework == "swiftui")
        #expect(cmd.limit == 6)
        #expect(cmd.format == .json)
        #expect(cmd.baseDir == "/tmp/base")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.platformFloors.minIos == "17.0")
        #expect(cmd.platformFloors.minMacos == "14.0")
        #expect(cmd.platformFloors.minTvos == "17.0")
        #expect(cmd.platformFloors.minWatchos == "10.0")
        #expect(cmd.platformFloors.minVisionos == "1.0")
    }

    @Test("search-conformances: retired --search-db flag is rejected (#1157)")
    func searchConformancesRejectsSearchDB() throws {
        var threw = false
        do {
            _ = try CLIImpl.Command.SearchConformances.parse(["--protocol", "View", "--search-db", "/tmp/x"])
        } catch {
            threw = true
        }
        #expect(threw, "search-conformances must reject the retired --search-db flag")
    }

    // MARK: - search-generics (AST)

    @Test("search-generics: every option parses + binds")
    func searchGenericsOptions() throws {
        let cmd = try CLIImpl.Command.SearchGenerics.parse([
            "--constraint", "Sendable",
            "--framework", "swift",
            "--limit", "20",
            "--format", "json",
            "--base-dir", "/tmp/base",
            "--source", "apple-docs",
            "--min-ios", "17.0",
            "--min-macos", "14.0",
            "--min-tvos", "17.0",
            "--min-watchos", "10.0",
            "--min-visionos", "1.0",
        ])
        #expect(cmd.constraint == "Sendable")
        #expect(cmd.framework == "swift")
        #expect(cmd.limit == 20)
        #expect(cmd.format == .json)
        #expect(cmd.baseDir == "/tmp/base")
        #expect(cmd.source == "apple-docs")
        #expect(cmd.platformFloors.minIos == "17.0")
        #expect(cmd.platformFloors.minMacos == "14.0")
        #expect(cmd.platformFloors.minTvos == "17.0")
        #expect(cmd.platformFloors.minWatchos == "10.0")
        #expect(cmd.platformFloors.minVisionos == "1.0")
    }

    @Test("search-generics: retired --search-db flag is rejected (#1157)")
    func searchGenericsRejectsSearchDB() throws {
        var threw = false
        do {
            _ = try CLIImpl.Command.SearchGenerics.parse(["--constraint", "Sendable", "--search-db", "/tmp/x"])
        } catch {
            threw = true
        }
        #expect(threw, "search-generics must reject the retired --search-db flag")
    }
}
