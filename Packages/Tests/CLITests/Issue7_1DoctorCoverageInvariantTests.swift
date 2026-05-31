@testable import CLI
import DistributionModels
import Foundation
import LoggingModels
import SearchModels
import SharedConstants
import Testing

// swiftlint:disable line_length
// (descriptive STATUS comments + #expect failure messages exceed the 120-char line guideline; readability beats wrapping here.)

// MARK: - 2026-05-26 audit Finding 7.1 — Doctor coverage invariant

//
// Pin: every production destinationDB has a corresponding
// `Distribution.DatabaseHealthCheck` conformer in Doctor.run's
// list. Pre-fix the list was hardcoded 3 (packages / samples / search)
// and the per-source DBs landed by #1036 (apple-documentation.db,
// hig.db, apple-archive.db, swift-evolution.db, swift-documentation.db)
// were silently un-probed.
//
// The conformer fakery here mirrors the production assembly logic
// rather than calling Doctor.run directly — invoking the live
// command would require mocking the entire Cupertino.Context, which
// is overkill for a coverage assertion.
//

private struct CoverageFake: Search.SourceProvider {
    let id: String
    let destination: Shared.Models.DatabaseDescriptor

    var definition: Search.SourceDefinition {
        Search.SourceDefinition(
            id: id,
            displayName: id,
            emoji: "🧪",
            properties: Search.SourceProperties(
                authority: 0.5, freshness: 0.5, comprehensiveness: 0.5,
                codeExamples: 0.5, hasAvailability: 0.0, designFocus: 0.0,
                languageFocus: 0.0, searchQuality: 0.5
            ),
            intents: [.howTo]
        )
    }

    var destinationDB: Shared.Models.DatabaseDescriptor {
        destination
    }

    var fetchInfo: Search.FetchInfo? {
        nil
    }

    var capabilities: Search.Capabilities {
        Search.Capabilities(searchers: [.text], operations: [.readByURI])
    }

    var legacySourceIDAliases: Set<String> {
        []
    }

    func makeStrategy(env _: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        preconditionFailure("CoverageFake never invokes makeStrategy")
    }

    func makeIndexer() -> any Search.SourceIndexer {
        preconditionFailure("CoverageFake never invokes makeIndexer")
    }
}

@Suite("Finding 7.1 — Doctor healthChecks coverage invariant")
struct Issue7_1DoctorCoverageInvariantTests {
    /// Reproduce Doctor.run's healthChecks assembly logic. The
    /// production version lives in `CLIImpl.Command.Doctor.run()` and
    /// is wrapped in command-handler scaffolding that isn't worth
    /// instantiating in a unit test; mirroring the assembly here is
    /// the same shape as `Issue1029StrategiesListRegistryDerivationTests`
    /// (which mirrors the strategies-list dispatcher).
    private static func assembleHealthChecks(
        registry: Search.SourceRegistry,
        paths: Shared.Paths,
        legacySearchDBURL: URL
    ) -> [any Distribution.DatabaseHealthCheck] {
        var healthChecks: [any Distribution.DatabaseHealthCheck] = [
            CLIImpl.Command.Doctor.PackagesHealthCheck(packagesDBURL: paths.packagesDatabase),
            CLIImpl.Command.Doctor.SamplesHealthCheck(samplesDBURL: paths.baseDirectory.appendingPathComponent(Shared.Models.DatabaseDescriptor.appleSampleCode.filename)),
            CLIImpl.Command.Doctor.SearchHealthCheck(
                descriptor: .search,
                dbURL: legacySearchDBURL,
                isRequired: true
            ),
        ]
        var seen: Set<String> = [
            Shared.Models.DatabaseDescriptor.search.id,
            Shared.Models.DatabaseDescriptor.packages.id,
            Shared.Models.DatabaseDescriptor.appleSampleCode.id,
        ]
        for provider in registry.allEnabled {
            let descriptor = provider.destinationDB
            guard !seen.contains(descriptor.id) else { continue }
            seen.insert(descriptor.id)
            healthChecks.append(CLIImpl.Command.Doctor.SearchHealthCheck(
                descriptor: descriptor,
                dbURL: paths.baseDirectory.appendingPathComponent(descriptor.filename),
                isRequired: false
            ))
        }
        return healthChecks
    }

    @Test("Every production destinationDB has a conformer in Doctor's healthChecks list")
    func everyProductionDestinationHasConformer() {
        let registry = CLIImpl.makeProductionSourceRegistry()
        let paths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/doctor-coverage"))
        let checks = Self.assembleHealthChecks(
            registry: registry,
            paths: paths,
            legacySearchDBURL: URL(fileURLWithPath: "/tmp/doctor-coverage/search.db")
        )
        let coveredDescriptorIDs = Set(checks.map(\.descriptor.id))
        let registeredDestinations = Set(registry.allEnabled.map(\.destinationDB.id))
        for destinationID in registeredDestinations {
            #expect(
                coveredDescriptorIDs.contains(destinationID),
                "Doctor.run's healthChecks list must include a conformer for every registered destinationDB; missing '\(destinationID)'. Adding a new source should automatically extend the list (regression marker for 2026-05-26 audit Finding 7.1)."
            )
        }
        // Legacy `.search` stays in the list as a transitional probe.
        #expect(coveredDescriptorIDs.contains(Shared.Models.DatabaseDescriptor.search.id))
    }

    @Test("A newly registered fake source's destinationDB shows up in healthChecks automatically")
    func newSourceFlowsToHealthChecks() {
        var registry = CLIImpl.makeProductionSourceRegistry()
        let fakeDB = Shared.Models.DatabaseDescriptor(
            id: "audit-7_1-fake",
            filename: "audit-7_1-fake.db",
            displayName: "Audit 7.1 Fake"
        )
        registry.register(CoverageFake(id: "audit-7_1-fake-src", destination: fakeDB))
        let paths = Shared.Paths(baseDirectory: URL(fileURLWithPath: "/tmp/doctor-coverage-fake"))
        let checks = Self.assembleHealthChecks(
            registry: registry,
            paths: paths,
            legacySearchDBURL: URL(fileURLWithPath: "/tmp/doctor-coverage-fake/search.db")
        )
        let coveredDescriptorIDs = Set(checks.map(\.descriptor.id))
        #expect(
            coveredDescriptorIDs.contains("audit-7_1-fake"),
            "Registering a fake source with a new destinationDB should automatically add its conformer to healthChecks; got coverage \(coveredDescriptorIDs.sorted())"
        )
        // Verify the new conformer's URL is correctly resolved
        // against the test paths, not hardcoded.
        let fakeCheck = checks.first { $0.descriptor.id == "audit-7_1-fake" }
        if let searchCheck = fakeCheck as? CLIImpl.Command.Doctor.SearchHealthCheck {
            #expect(searchCheck.dbURL.path == "/tmp/doctor-coverage-fake/audit-7_1-fake.db")
            #expect(searchCheck.isRequired == false, "per-source DBs default to warning-only; only legacy .search is hard-required")
        } else {
            Issue.record("New conformer should be SearchHealthCheck-shaped; got \(type(of: fakeCheck))")
        }
    }

    @Test("printSchemaVersions entries list is also registry-derived (covers Finding 7.2)")
    func printSchemaVersionsCoversNewSources() {
        // The entries assembly logic in `printSchemaVersions` mirrors
        // the healthChecks assembly — same registry iteration with
        // .packages / .appleSampleCode special-case path resolvers.
        // Verify the same coverage invariance.
        var registry = CLIImpl.makeProductionSourceRegistry()
        let fakeDB = Shared.Models.DatabaseDescriptor(
            id: "audit-7_2-fake",
            filename: "audit-7_2-fake.db",
            displayName: "Audit 7.2 Fake"
        )
        registry.register(CoverageFake(id: "audit-7_2-fake-src", destination: fakeDB))
        let docsBase = URL(fileURLWithPath: "/tmp/schema-versions-fake")
        var entries: [(Shared.Models.DatabaseDescriptor, URL)] = [
            (.search, docsBase.appendingPathComponent("search.db")),
        ]
        var seen: Set<String> = [Shared.Models.DatabaseDescriptor.search.id]
        for provider in registry.allEnabled {
            let descriptor = provider.destinationDB
            guard !seen.contains(descriptor.id) else { continue }
            seen.insert(descriptor.id)
            let url: URL
            if descriptor == .packages {
                url = docsBase.appendingPathComponent(descriptor.filename)
            } else if descriptor == .appleSampleCode {
                url = docsBase.appendingPathComponent(descriptor.filename)
            } else {
                url = docsBase.appendingPathComponent(descriptor.filename)
            }
            entries.append((descriptor, url))
        }
        let coveredIDs = Set(entries.map(\.0.id))
        #expect(
            coveredIDs.contains("audit-7_2-fake"),
            "printSchemaVersions entries list must auto-include a registered fake source's destinationDB (regression marker for 2026-05-26 audit Finding 7.2)."
        )
    }
}
