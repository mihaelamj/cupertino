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

        // 13 visible + 1 hidden (package-search) + `inheritance` (#274)
        // + `search-symbols` (#948 phase 1) + list browse commands (#1208/#1210).
        // `setup` now owns every
        // database (packages-setup was collapsed into it). `resolve-refs`
        // post-processes saved pages against #208. `index` removed in
        // #231 (samples now build via `save --samples`). `ask` absorbed
        // into `search` in #239 (default fan-out path produces the same
        // chunked output as `ask` did). `inheritance` added in #274
        // (walks the class-inheritance edge table introduced at schema
        // v15). `search-symbols` (#948 phase 1) + `search-property-
        // wrappers` (#948 phase 2) + `search-concurrency` /
        // `search-conformances` / `search-generics` (#948 phases 3-5)
        // complete the 5-AST-tool CLI surface mirroring the MCP tools.
        #expect(config.subcommands.count == 23)
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Setup.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Fetch.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Save.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Serve.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Search.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Read.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ListFrameworks.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ListDocuments.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ListChildren.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ListSources.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ListSamples.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ReadSample.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ReadSampleFile.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Doctor.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Cleanup.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.PackageSearch.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.ResolveRefs.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.Inheritance.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.SearchSymbols.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.SearchPropertyWrappers.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.SearchConcurrency.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.SearchConformances.self })
        #expect(config.subcommands.contains { $0 == CLIImpl.Command.SearchGenerics.self })
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

    @Test("#1201 — save --help source-to-DB mapping is registry-generated, not a hardcoded swift-documentation.db")
    func saveHelpDispatchMappingIsRegistryGenerated() {
        let discussion = CLIImpl.Command.Save.configuration.discussion
        // The mapping is generated from makeProductionSourceRegistry(); each
        // enabled source's `definition.id` -> `destinationDB.filename` line
        // must appear, proving no hardcoded database literal.
        #expect(discussion.contains("`--source apple-docs` builds apple-documentation.db"))
        #expect(discussion.contains("`--source swift-org` builds swift-org.db"))
        #expect(discussion.contains("`--source swift-book` builds swift-book.db"))
        #expect(discussion.contains("`--source samples` builds apple-sample-code.db"))
        #expect(discussion.contains("`--source packages` builds packages.db"))
        // Post-#1038 swift-org and swift-book are separate DBs; the pre-#1038
        // shared file must not resurface.
        #expect(
            !discussion.contains("swift-documentation.db"),
            "save help must not reference the pre-#1038 shared swift-documentation.db"
        )
    }

    @Test("Abstract description exists")
    func abstractExists() {
        let config = Cupertino.configuration
        #expect(!config.abstract.isEmpty)
        #expect(config.abstract.contains("MCP"))
    }

    @Test("help text does not enumerate the legacy unified search.db / samples.db (v1.3.0 per-source split)")
    func helpTextFreeOfLegacyUnifiedDBNames() {
        // The root command summary, `setup` abstract, and `doctor` discussion
        // used to enumerate `search.db` / `samples.db`; post-v1.3.0 those are
        // per-source databases. The help describes them generically so adding
        // a source needs no edit here. (`search --search-db` legitimately
        // still mentions the legacy monolithic DB for the migration window,
        // so it is intentionally not covered by this guard.)
        let root = Cupertino.configuration.discussion
        #expect(!root.contains("search.db"), "root help must not name the legacy unified search.db")
        #expect(!root.contains("samples.db"), "root help must not name samples.db (now apple-sample-code.db)")

        let setup = CLIImpl.Command.Setup.configuration.abstract
        #expect(!setup.contains("search.db"))
        #expect(!setup.contains("samples.db"))

        let doctor = CLIImpl.Command.Doctor.configuration.discussion
        #expect(!doctor.contains("search.db"), "doctor help discussion must not name the legacy unified search.db")
        #expect(!doctor.contains("samples.db"))
    }

    @Test("the removed --search-db flag is rejected on every command that used to carry it")
    func searchDBFlagRejectedEverywhere() {
        func rejects(_ parse: () throws -> Void) -> Bool {
            do { try parse(); return false } catch { return true }
        }
        #expect(rejects { _ = try CLIImpl.Command.Search.parse(["View", "--search-db", "/tmp/x"]) })
        #expect(rejects { _ = try CLIImpl.Command.Read.parse(["apple-docs://swift/array", "--search-db", "/tmp/x"]) })
        #expect(rejects { _ = try CLIImpl.Command.Save.parse(["--source", "apple-docs", "--search-db", "/tmp/x"]) })
        #expect(rejects { _ = try CLIImpl.Command.Doctor.parse(["--search-db", "/tmp/x"]) })
        #expect(rejects { _ = try CLIImpl.Command.ListFrameworks.parse(["--search-db", "/tmp/x"]) })
        #expect(rejects { _ = try CLIImpl.Command.ListDocuments.parse(["--framework", "swiftui", "--search-db", "/tmp/x"]) })
        #expect(rejects { _ = try CLIImpl.Command.ListChildren.parse(["apple-docs://swiftui", "--search-db", "/tmp/x"]) })
        #expect(rejects { _ = try CLIImpl.Command.Inheritance.parse(["UIButton", "--search-db", "/tmp/x"]) })
    }
}

// MARK: - FetchType Enum Tests (dissolved post-#1031)

// Pre-#1031 the `FetchTypeTests` + `FetchTypeDisplayNameTests` suites
// here pinned the `Cupertino.FetchType` enum's metadata (display name,
// default output dir, web-crawl categorization, raw values, default
// URLs). Phase 1I.c.2 of #1007 dissolved that enum entirely; the
// per-type metadata now lives in each per-source target's `*.FetchInfo.swift`
// (covered by `Issue1014AppleArchiveSourceShapeTests`,
// `Issue1019SwiftOrgSourceShapeTests`, `Issue1021SwiftBookSourceShapeTests`,
// `Issue1023PackagesSourceShapeTests`, and the per-source target's own
// fetchInfo pin) and the `cupertino fetch --source <id>` CLI dispatches
// on canonical source-id strings.

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
