import Foundation
import LoggingModels
@testable import SampleIndex
import SharedConstants
import Testing

// MARK: - #732 — Sample.Index.Database.searchProjects platform filter

// `Sample.Index.Database.searchProjects` grew a 5-field platform filter
// (`minIOS` / `minMacOS` / `minTvOS` / `minWatchOS` / `minVisionOS`).
// Multiple values AND-combine — a project must satisfy every requested
// minimum to pass. The filter applies via
// `AND projects.min_<platform> IS NOT NULL AND p.min_<platform> <= ?`
// per-platform clauses bound in lock-step.
//
// These tests pin the SQL contract end-to-end against a real on-disk
// sample DB: index two projects with distinct deployment targets, run
// `searchProjects` with each kind of filter combination, assert the
// result set matches expectations row-for-row.

@Suite("#732 — Sample.Index.Database.searchProjects platform filter")
struct Issue732SearchProjectsPlatformFilterTests {
    /// Seed a temp DB with three projects:
    /// - `ios-15` runs on iOS 15+ only
    /// - `ios-17-macos-14` runs on iOS 17+ AND macOS 14+
    /// - `legacy` has no deployment-target metadata (NULL min_*)
    private static func seedDatabase() async throws -> (database: Sample.Index.Database, cleanup: () -> Void) {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue732-\(UUID().uuidString).db")
        let database = try await Sample.Index.Database(dbPath: dbURL, logger: Logging.NoopRecording())

        try await database.indexProject(Sample.Index.Project(
            id: "ios-15",
            title: "iOS 15 sample",
            description: "Sample that requires iOS 15 or later",
            frameworks: ["swiftui"],
            readme: nil,
            webURL: "https://example.com/ios-15",
            zipFilename: "ios-15.zip",
            fileCount: 1,
            totalSize: 100,
            deploymentTargets: ["iOS": "15.0"],
            availabilitySource: "sample-swift"
        ))

        try await database.indexProject(Sample.Index.Project(
            id: "ios-17-macos-14",
            title: "iOS 17 macOS 14 sample",
            description: "Sample requiring iOS 17 and macOS 14",
            frameworks: ["swiftui"],
            readme: nil,
            webURL: "https://example.com/ios-17-macos-14",
            zipFilename: "ios-17-macos-14.zip",
            fileCount: 1,
            totalSize: 200,
            deploymentTargets: ["iOS": "17.0", "macOS": "14.0"],
            availabilitySource: "sample-swift"
        ))

        try await database.indexProject(Sample.Index.Project(
            id: "legacy",
            title: "Legacy sample",
            description: "Sample without deployment targets",
            frameworks: ["swiftui"],
            readme: nil,
            webURL: "https://example.com/legacy",
            zipFilename: "legacy.zip",
            fileCount: 1,
            totalSize: 50
        ))

        return (database, {
            Task { await database.disconnect() }
            try? FileManager.default.removeItem(at: dbURL)
        })
    }

    @Test("No filter set — all 3 projects returned")
    func noFilterReturnsAll() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: nil,
            limit: 20
        )
        #expect(results.count == 3, "expected all 3 seeded projects")
    }

    @Test("minIOS=15.0 — keeps the two projects with min_ios <= 15.0")
    func minIOS15FiltersCorrectly() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: nil,
            limit: 20,
            minIOS: "15.0",
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil
        )
        // ios-15 has min_ios=15.0 (passes 15.0 <= 15.0)
        // ios-17-macos-14 has min_ios=17.0 (fails 17.0 <= 15.0)
        // legacy has NULL min_ios (rejected by IS NOT NULL gate)
        let ids = results.map(\.id).sorted()
        #expect(ids == ["ios-15"], "expected only ios-15 to pass user-on-iOS-15 filter; got \(ids)")
    }

    @Test("minIOS=18.0 — both iOS-axis projects pass the user-on-iOS-18 filter")
    func minIOS18AcceptsBoth() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: nil,
            limit: 20,
            minIOS: "18.0",
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil
        )
        // 15.0 <= 18.0 ✓ AND 17.0 <= 18.0 ✓; legacy still rejected (NULL).
        let ids = results.map(\.id).sorted()
        #expect(ids == ["ios-15", "ios-17-macos-14"])
    }

    @Test("minIOS=18.0 + minMacOS=14.0 — AND-combines, only ios-17-macos-14 has both")
    func andCombinationRequiresBoth() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: nil,
            limit: 20,
            minIOS: "18.0",
            minMacOS: "14.0",
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil
        )
        // ios-15 has NULL min_macos → rejected by macOS IS NOT NULL gate
        // ios-17-macos-14 has both: 17.0 <= 18.0 ✓ AND 14.0 <= 14.0 ✓
        // legacy NULL on both
        let ids = results.map(\.id).sorted()
        #expect(ids == ["ios-17-macos-14"], "AND should require both columns populated + lex-≤; got \(ids)")
    }

    @Test("minIOS=10.0 — rejects all (user too old for iOS 15+ project)")
    func minIOS10RejectsAll() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: nil,
            limit: 20,
            minIOS: "10.0",
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil
        )
        // No project's min_ios <= 10.0
        #expect(results.isEmpty)
    }

    @Test("Platform with no data — rejects all (NULL gate)")
    func platformWithNoDataReturnsEmpty() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: nil,
            limit: 20,
            minIOS: nil,
            minMacOS: nil,
            minTvOS: "17.0", // none of the seeded projects has min_tvos
            minWatchOS: nil,
            minVisionOS: nil
        )
        #expect(results.isEmpty, "no seeded project has min_tvos populated — all rejected by IS NOT NULL")
    }

    @Test("Legacy 3-arg overload (back-compat) returns all")
    func legacyOverloadStillWorks() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        // The protocol extension on Sample.Index.Reader provides a
        // 3-arg overload with no platform args. Callers that haven't
        // been migrated compile unchanged.
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: nil,
            limit: 20
        )
        #expect(results.count == 3)
    }

    @Test("Framework filter composes with platform filter (AND)")
    func frameworkAndPlatformFilterCompose() async throws {
        let (database, cleanup) = try await Self.seedDatabase()
        defer { cleanup() }
        let results = try await database.searchProjects(
            query: "swiftui",
            framework: "swiftui",
            limit: 20,
            minIOS: "15.0",
            minMacOS: nil,
            minTvOS: nil,
            minWatchOS: nil,
            minVisionOS: nil
        )
        // Framework filter matches all 3; platform filter keeps only
        // ios-15. AND combination yields just ios-15.
        let ids = results.map(\.id).sorted()
        #expect(ids == ["ios-15"])
    }
}
