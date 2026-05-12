import Foundation
@testable import SampleIndex
import SharedConstants
import Testing

@Suite("SampleIndex Tests")
struct SampleIndexTests {
    @Test("Project ID extraction from filename")
    func projectIdFromFilename() {
        // Test that the File model extracts path components correctly
        let file = Sample.Index.File(
            projectId: "test-project",
            path: "Sources/Views/ContentView.swift",
            content: "import SwiftUI"
        )

        #expect(file.filename == "ContentView.swift")
        #expect(file.folder == "Sources/Views")
        #expect(file.fileExtension == "swift")
        #expect(file.projectId == "test-project")
    }

    @Test("Indexable file extensions")
    func indexableExtensions() {
        // Swift files should be indexed
        #expect(Sample.Index.shouldIndex(path: "main.swift"))
        #expect(Sample.Index.shouldIndex(path: "ViewController.m"))
        #expect(Sample.Index.shouldIndex(path: "Header.h"))

        // Binary files should not be indexed
        #expect(!Sample.Index.shouldIndex(path: "image.png"))
        #expect(!Sample.Index.shouldIndex(path: "model.usdz"))
        #expect(!Sample.Index.shouldIndex(path: "binary.dat"))
    }

    @Test("Project model creation")
    func projectModel() {
        let project = Sample.Index.Project(
            id: "sample-app",
            title: "Sample App",
            description: "A sample application",
            frameworks: ["SwiftUI", "Combine"],
            readme: "# Sample App\n\nA demo.",
            webURL: "https://developer.apple.com/sample",
            zipFilename: "sample-app.zip",
            fileCount: 10,
            totalSize: 5000
        )

        #expect(project.id == "sample-app")
        #expect(project.frameworks == ["swiftui", "combine"]) // lowercased
        #expect(project.fileCount == 10)
    }
}

// MARK: - #228 phase 2: availability columns on samples.db

@Suite("samples.db availability persistence (#228 phase 2)")
struct SamplesAvailabilityPersistenceTests {
    @Test("Project carries deployment targets + availability source")
    func projectInitWithAvailability() {
        let project = Sample.Index.Project(
            id: "swiftui-list",
            title: "SwiftUI List",
            description: "Sample showing List",
            frameworks: ["swiftui"],
            readme: nil,
            webURL: "https://example.com",
            zipFilename: "swiftui-list.zip",
            fileCount: 1,
            totalSize: 100,
            deploymentTargets: ["iOS": "17.0", "macOS": "14.0"],
            availabilitySource: "sample-swift"
        )
        #expect(project.deploymentTargets["iOS"] == "17.0")
        #expect(project.deploymentTargets["macOS"] == "14.0")
        #expect(project.availabilitySource == "sample-swift")
    }

    @Test("Project default init leaves availability empty + nil")
    func projectInitWithoutAvailability() {
        let project = Sample.Index.Project(
            id: "x",
            title: "x",
            description: "x",
            frameworks: [],
            readme: nil,
            webURL: "",
            zipFilename: "x.zip",
            fileCount: 0,
            totalSize: 0
        )
        #expect(project.deploymentTargets.isEmpty)
        #expect(project.availabilitySource == nil)
    }

    @Test("File carries availableAttrsJSON when supplied")
    func fileInitWithAttrs() {
        let json = "[{\"line\":12,\"raw\":\"(iOS 17, *)\",\"platforms\":[\"iOS\",\"*\"]}]"
        let file = Sample.Index.File(
            projectId: "p",
            path: "Sources/Foo.swift",
            content: "import SwiftUI",
            availableAttrsJSON: json
        )
        #expect(file.availableAttrsJSON == json)
    }

    @Test("File default init leaves availableAttrsJSON nil")
    func fileInitWithoutAttrs() {
        let file = Sample.Index.File(
            projectId: "p",
            path: "Sources/Foo.swift",
            content: "import SwiftUI"
        )
        #expect(file.availableAttrsJSON == nil)
    }

    @Test("Database round-trip: project availability columns survive store + read")
    func databaseRoundtrip() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samples-roundtrip-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let database = try await Sample.Index.Database(dbPath: dbURL)
        defer { Task { await database.disconnect() } }

        let project = Sample.Index.Project(
            id: "test-roundtrip",
            title: "Test",
            description: "Test desc",
            frameworks: ["swiftui"],
            readme: nil,
            webURL: "https://example.com/test",
            zipFilename: "test.zip",
            fileCount: 1,
            totalSize: 50,
            deploymentTargets: ["iOS": "16.0"],
            availabilitySource: "sample-swift"
        )
        try await database.indexProject(project)

        let fetched = try await database.getProject(id: "test-roundtrip")
        #expect(fetched?.deploymentTargets["iOS"] == "16.0")
        #expect(fetched?.availabilitySource == "sample-swift")
    }

    @Test("Database round-trip: file availableAttrsJSON survives store + read")
    func databaseFileRoundtrip() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samples-file-roundtrip-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let database = try await Sample.Index.Database(dbPath: dbURL)
        defer { Task { await database.disconnect() } }

        let project = Sample.Index.Project(
            id: "p1",
            title: "x",
            description: "x",
            frameworks: [],
            readme: nil,
            webURL: "",
            zipFilename: "p1.zip",
            fileCount: 1,
            totalSize: 100
        )
        try await database.indexProject(project)

        let json = "[{\"line\":7,\"raw\":\"(iOS 17, *)\",\"platforms\":[\"iOS\",\"*\"]}]"
        let file = Sample.Index.File(
            projectId: "p1",
            path: "Sources/Foo.swift",
            content: "@available(iOS 17, *) func foo() {}",
            availableAttrsJSON: json
        )
        try await database.indexFile(file)

        let fetched = try await database.getFile(projectId: "p1", path: "Sources/Foo.swift")
        #expect(fetched?.availableAttrsJSON == json)
    }
}
