import Foundation
import LoggingModels
import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
@testable import Services
import SharedConstants
import Testing

/// Regression suite for [#1130](https://github.com/mihaelamj/cupertino/issues/1130).
///
/// `cupertino search --source samples --min-ios N` silently dropped the
/// platform filter: `CLIImpl.Command.Search.SourceRunners.runSampleSearch`
/// built `Sample.Search.Query` WITHOUT the 5 `min<Platform>` fields, so
/// every N returned the same unfiltered set. The CLI lives in a
/// downstream target that talks to stdout and isn't unit-testable
/// end-to-end; this suite pins the `Sample.Search.Service.search`
/// contract the CLI fix relies on — namely that a `Sample.Search.Query`
/// carrying `minIOS` actually filters. The fix is wiring the CLI flags
/// into this Query; these tests prove the Query → service → DB path
/// honours them.
@Suite("#1130 Sample.Search.Service platform-filter contract", .serialized)
struct Issue1130SampleSearchPlatformFilterTests {
    private static func seed() async throws -> (Sample.Index.Database, () -> Void) {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1130-\(UUID().uuidString).db")
        let db = try await Sample.Index.Database(dbPath: dbURL, logger: Logging.NoopRecording())
        try await db.indexProject(Sample.Index.Project(
            id: "ios-14", title: "iOS 14 sample", description: "needs iOS 14",
            frameworks: ["swiftui"], readme: nil, webURL: "https://example.com/14",
            zipFilename: "ios-14.zip", fileCount: 1, totalSize: 100,
            deploymentTargets: ["iOS": "14.0"], availabilitySource: "sample-available-aggregated"
        ))
        try await db.indexProject(Sample.Index.Project(
            id: "ios-18", title: "iOS 18 sample", description: "needs iOS 18",
            frameworks: ["swiftui"], readme: nil, webURL: "https://example.com/18",
            zipFilename: "ios-18.zip", fileCount: 1, totalSize: 200,
            deploymentTargets: ["iOS": "18.0"], availabilitySource: "sample-available-aggregated"
        ))
        return (db, {
            Task { await db.disconnect() }
            try? FileManager.default.removeItem(at: dbURL)
        })
    }

    @Test("Query with no minIOS returns both samples")
    func noFilterReturnsBoth() async throws {
        let (db, cleanup) = try await Self.seed()
        defer { cleanup() }
        let service = Sample.Search.Service(database: db)
        let result = try await service.search(Sample.Search.Query(text: "swiftui", searchFiles: false))
        #expect(result.projects.count == 2)
    }

    @Test("Query with minIOS=15 excludes the iOS-18 sample (only iOS-14 passes)")
    func minIOS15FiltersToiOS14() async throws {
        let (db, cleanup) = try await Self.seed()
        defer { cleanup() }
        let service = Sample.Search.Service(database: db)
        let result = try await service.search(
            Sample.Search.Query(text: "swiftui", searchFiles: false, minIOS: "15.0")
        )
        let ids = Set(result.projects.map(\.id))
        #expect(ids == ["ios-14"], "minIOS=15 should keep only the iOS-14 sample, got \(ids)")
    }

    @Test("Query with minIOS=18 keeps both (both floors <= 18)")
    func minIOS18KeepsBoth() async throws {
        let (db, cleanup) = try await Self.seed()
        defer { cleanup() }
        let service = Sample.Search.Service(database: db)
        let result = try await service.search(
            Sample.Search.Query(text: "swiftui", searchFiles: false, minIOS: "18.0")
        )
        #expect(result.projects.count == 2)
    }

    @Test("Query with minIOS=10 excludes both (no sample floor <= 10)")
    func minIOS10ExcludesBoth() async throws {
        let (db, cleanup) = try await Self.seed()
        defer { cleanup() }
        let service = Sample.Search.Service(database: db)
        let result = try await service.search(
            Sample.Search.Query(text: "swiftui", searchFiles: false, minIOS: "10.0")
        )
        #expect(result.projects.isEmpty, "minIOS=10 should exclude both iOS-14 + iOS-18 samples")
    }
}
