import DistributionModels
import Foundation
import SharedConstants
import Testing

// MARK: - #919 coverage pins: Distribution.SetupService.Outcome edge cases

@Suite("#919 coverage: Distribution.SetupService.Outcome lookup contract")
struct Issue919OutcomeLookupTests {
    private static let dbURL: Shared.Models.DatabaseDescriptor = .search
    private static let samplesDB: Shared.Models.DatabaseDescriptor = .samples
    private static let packagesDB: Shared.Models.DatabaseDescriptor = .packages

    private static func makeOutcome(
        placements: [Distribution.SetupService.DatabasePlacement]? = nil
    ) -> Distribution.SetupService.Outcome {
        let defaults: [Distribution.SetupService.DatabasePlacement] = [
            .init(descriptor: Self.dbURL, path: URL(fileURLWithPath: "/tmp/search.db")),
            .init(descriptor: Self.samplesDB, path: URL(fileURLWithPath: "/tmp/samples.db")),
            .init(descriptor: Self.packagesDB, path: URL(fileURLWithPath: "/tmp/packages.db")),
        ]
        return Distribution.SetupService.Outcome(
            databases: placements ?? defaults,
            docsVersionWritten: "1.2.0",
            skippedDownload: false,
            priorStatus: .missing
        )
    }

    @Test("path(forDatabaseId:) returns nil for an unknown id")
    func unknownIdReturnsNil() {
        let outcome = Self.makeOutcome()
        #expect(outcome.path(forDatabaseId: "definitely-not-a-db") == nil)
        #expect(outcome.path(forDatabaseId: "") == nil)
        #expect(outcome.path(forDatabaseId: "Search") == nil) // case-sensitive: capital S
    }

    @Test("path(forDatabaseId:) returns the expected URL for each of the 3 known ids")
    func knownIdsResolve() {
        let outcome = Self.makeOutcome()
        #expect(outcome.path(forDatabaseId: "search")?.lastPathComponent == "search.db")
        #expect(outcome.path(forDatabaseId: "samples")?.lastPathComponent == "samples.db")
        #expect(outcome.path(forDatabaseId: "packages")?.lastPathComponent == "packages.db")
    }

    @Test("path(forDatabaseId:) returns nil when the descriptor exists but isn't in this Outcome")
    func descriptorNotInOutcome() {
        // Outcome with only the search placement; ask for packages.
        let placements: [Distribution.SetupService.DatabasePlacement] = [
            .init(descriptor: Self.dbURL, path: URL(fileURLWithPath: "/tmp/search.db")),
        ]
        let outcome = Self.makeOutcome(placements: placements)
        #expect(outcome.path(forDatabaseId: "search")?.lastPathComponent == "search.db")
        #expect(outcome.path(forDatabaseId: "packages") == nil)
        #expect(outcome.path(forDatabaseId: "samples") == nil)
    }

    @Test("Outcome equality is order-sensitive on the databases array (documented contract)")
    func equalityIsOrderSensitive() {
        let orderA = Self.makeOutcome(placements: [
            .init(descriptor: Self.dbURL, path: URL(fileURLWithPath: "/tmp/s.db")),
            .init(descriptor: Self.samplesDB, path: URL(fileURLWithPath: "/tmp/sa.db")),
        ])
        let orderB = Self.makeOutcome(placements: [
            .init(descriptor: Self.samplesDB, path: URL(fileURLWithPath: "/tmp/sa.db")),
            .init(descriptor: Self.dbURL, path: URL(fileURLWithPath: "/tmp/s.db")),
        ])
        // Pre-#919 the Outcome carried 3 named fields; equality compared
        // each independently. Post-#919 it carries an Array of
        // placements; Equatable derives element-wise + order-sensitive.
        // This is documented in the Outcome docstring; the test pins it.
        #expect(orderA != orderB)
    }
}
