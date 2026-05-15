import Foundation
import LoggingModels
import SampleIndex
import SampleIndexModels
@testable import Services
import SharedConstants
import Testing

/// Regression suite for [#620](https://github.com/mihaelamj/cupertino/issues/620).
///
/// The CLI's `read-sample-file` command (`CLIImpl.Command.ReadSampleFile`)
/// now probes `Sample.Search.Service.getProject(id:)` before the file
/// lookup so the error message distinguishes "wrong project id" from
/// "wrong file path inside a valid project". This suite pins the
/// `getProject` contract the CLI fix depends on — the CLI lives in a
/// downstream target and isn't unit-testable end-to-end (it talks to
/// stdout via `Cupertino.Context.composition.logging.recording`), but
/// the service-layer behaviour these tests pin is the load-bearing
/// piece.
@Suite("#620 Sample.Search.Service project-lookup contract", .serialized)
struct Issue620SampleServiceProjectLookupTests {
    @Test("getProject(id:) returns nil for an unknown id on an empty DB")
    func unknownIdReturnsNilOnEmptyDB() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue620-empty-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let database = try await Sample.Index.Database(dbPath: dbURL, logger: Logging.NoopRecording())
        let service = Sample.Search.Service(database: database)
        defer { Task { await service.disconnect() } }

        let project = try await service.getProject(id: "no-such-project")
        #expect(
            project == nil,
            "getProject must return nil for an id that doesn't exist (the CLI fix branches on this nil to emit 'Project not found' instead of the file-not-found shape)"
        )
    }

    @Test("getProject(id:) returns nil for an adjacent-but-different id; returns the project for the exact id")
    func mismatchedIdReturnsNilExactIdHits() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue620-mismatch-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let database = try await Sample.Index.Database(dbPath: dbURL, logger: Logging.NoopRecording())

        try await database.indexProject(Sample.Index.Project(
            id: "real-project-id",
            title: "Real Project",
            description: "Seeded for the test",
            frameworks: ["swiftui"],
            readme: nil,
            webURL: "https://example.com/x",
            zipFilename: "real.zip",
            fileCount: 0,
            totalSize: 0
        ))

        let service = Sample.Search.Service(database: database)
        defer { Task { await service.disconnect() } }

        let miss = try await service.getProject(id: "different-project-id")
        #expect(miss == nil)

        let hit = try await service.getProject(id: "real-project-id")
        #expect(hit != nil)
        #expect(hit?.id == "real-project-id")
        #expect(hit?.title == "Real Project")
    }

    @Test("getFile(projectId:path:) returns nil for an unknown path inside a real project — the file-not-found shape")
    func validProjectInvalidPathReturnsNil() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue620-validproject-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let database = try await Sample.Index.Database(dbPath: dbURL, logger: Logging.NoopRecording())

        try await database.indexProject(Sample.Index.Project(
            id: "host-project",
            title: "Host",
            description: "",
            frameworks: ["swiftui"],
            readme: nil,
            webURL: "https://example.com/host",
            zipFilename: "host.zip",
            fileCount: 1,
            totalSize: 32
        ))
        try await database.indexFile(Sample.Index.File(
            projectId: "host-project",
            path: "Sources/Main.swift",
            content: "// hello"
        ))

        let service = Sample.Search.Service(database: database)
        defer { Task { await service.disconnect() } }

        // Project exists; file path does NOT — getProject + getFile combination
        // is the CLI branch that prints 'File not found in project'.
        let project = try await service.getProject(id: "host-project")
        #expect(project != nil, "project must exist for this test path")

        let missing = try await service.getFile(projectId: "host-project", path: "Sources/DoesNotExist.swift")
        #expect(missing == nil, "getFile must return nil for an unknown path inside a real project")

        // Happy path: file exists, content round-trips.
        let found = try await service.getFile(projectId: "host-project", path: "Sources/Main.swift")
        #expect(found != nil)
        #expect(found?.content == "// hello")
    }
}
