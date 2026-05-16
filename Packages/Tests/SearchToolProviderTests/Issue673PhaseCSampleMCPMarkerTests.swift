import Foundation
import LoggingModels
import MCPCore
@testable import SampleIndex
@testable import Search
import SearchModels
@testable import SearchToolProvider
import SharedConstants
import Testing

/// Phase C iter-8 of #673. Final iteration of the MCP semantic-marker
/// coverage — pins the **3 sample-database-backed tools**, bringing total
/// to **11 of 11 registered MCP tools fully pinned**.
///
/// Tools pinned by this PR:
///
/// - `list_samples` — title `"# Indexed Sample Code Projects"`,
///   totals lines `"Total projects:"` + `"Total files:"`, empty marker
///   `"_No projects found. Run \`cupertino save --samples\`..."`,
///   table header `"| Project | Framework | Files |"`.
/// - `read_sample` — title `"# \(project.title)"`, sections
///   `"## Description"` / `"## Metadata"` / `"## README"` / `"## Files"`,
///   project-id marker `"**Project ID:** \`..\`"`.
/// - `read_sample_file` — title `"# \(filename)"`, fence with language,
///   `"**Project:**"` + `"**Path:**"` markers.
@Suite("#673 Phase C iter-8 — sample-side MCP semantic markers (11/11 complete)")
struct Issue673PhaseCSampleMCPMarkerTests {
    private static func tempBaseDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue673-iter8-\(UUID().uuidString)")
    }

    /// Build a `CompositeToolProvider` over a fresh sample DB. `searchIndex`
    /// is nil because the sample-side tools only need `sampleDatabase`.
    private static func makeProvider(
        seed: (Sample.Index.Database) async throws -> Void
    ) async throws -> (provider: CompositeToolProvider, cleanup: () -> Void) {
        let tempDir = Self.tempBaseDir()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("samples.db")
        let database = try await Sample.Index.Database(dbPath: dbPath, logger: Logging.NoopRecording())
        try await seed(database)
        let provider = CompositeToolProvider(searchIndex: nil, sampleDatabase: database)
        return (provider, {
            try? FileManager.default.removeItem(at: tempDir)
        })
    }

    private static func seedProject(
        on database: Sample.Index.Database,
        id: String,
        title: String,
        frameworks: [String],
        fileCount: Int = 1
    ) async throws {
        let project = Sample.Index.Project(
            id: id,
            title: title,
            description: "Test project: \(title).",
            frameworks: frameworks,
            readme: "# \(title)\n\nReadme content for \(title).",
            webURL: "https://developer.apple.com/documentation/samplecode/\(id)",
            zipFilename: "\(id).zip",
            fileCount: fileCount,
            totalSize: 12345
        )
        try await database.indexProject(project)
    }

    private static func seedFile(
        on database: Sample.Index.Database,
        projectId: String,
        path: String,
        content: String
    ) async throws {
        let file = Sample.Index.File(
            projectId: projectId,
            path: path,
            content: content
        )
        try await database.indexFile(file)
    }

    // MARK: - list_samples

    @Test("list_samples empty: '# Indexed Sample Code Projects' header + empty-projects marker")
    func listSamplesEmpty() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in
            // Empty DB
        }
        defer { cleanup() }
        let result = try await provider.callTool(name: "list_samples", arguments: [:])
        guard case let .text(t) = result.content.first else {
            Issue.record("expected text content")
            return
        }
        #expect(
            t.text.contains("# Indexed Sample Code Projects"),
            "list_samples must contain canonical header — body: \(t.text.prefix(300))"
        )
        #expect(t.text.contains("Total projects:"))
        #expect(t.text.contains("Total files:"))
        #expect(
            t.text.contains("_No projects found. Run `cupertino save --samples`"),
            "empty-projects marker missing — body: \(t.text.prefix(300))"
        )
        // Negative: empty path must NOT emit the populated-table header.
        #expect(!t.text.contains("| Project | Framework | Files |"))
    }

    @Test("list_samples populated: table header + each seeded project row")
    func listSamplesPopulated() async throws {
        let (provider, cleanup) = try await Self.makeProvider { db in
            try await Self.seedProject(
                on: db,
                id: "swiftui-animations",
                title: "Animating Views",
                frameworks: ["SwiftUI"]
            )
            try await Self.seedProject(
                on: db,
                id: "combine-publishers",
                title: "Combine Publishers",
                frameworks: ["Combine", "SwiftUI"]
            )
        }
        defer { cleanup() }
        let result = try await provider.callTool(name: "list_samples", arguments: [:])
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        // Diagnostic dump on assertion failure so the next test author
        // can see what shape the handler emits.
        let body = t.text
        #expect(
            body.contains("# Indexed Sample Code Projects"),
            "header missing — body: \(body)"
        )
        #expect(
            body.contains("| Project | Framework | Files |"),
            "populated response must contain table header — body: \(body)"
        )
        #expect(
            body.contains("`swiftui-animations`"),
            "project id row missing — body: \(body)"
        )
        #expect(
            body.contains("`combine-publishers`"),
            "second project id row missing — body: \(body)"
        )
        // Sample.Index.Project.init lowercases `frameworks`; the body
        // emits "swiftui" / "combine", not the input casing.
        #expect(body.contains("swiftui"))
        #expect(body.contains("combine"))
        // Footer tip.
        #expect(t.text.contains("source: samples"))
    }

    // MARK: - read_sample

    @Test("read_sample: missing project_id arg throws ToolError")
    func readSampleMissingArg() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "read_sample", arguments: [:])
        }
    }

    @Test("read_sample: not-found project throws ToolError with 'Project not found'")
    func readSampleNotFoundThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "project_id": MCP.Core.Protocols.AnyCodable("nonexistent-project"),
        ]
        do {
            _ = try await provider.callTool(name: "read_sample", arguments: args)
            Issue.record("expected throw")
        } catch {
            let desc = "\(error)"
            #expect(
                desc.contains("Project not found") || desc.contains("not found"),
                "not-found error must carry 'not found' marker — got: \(desc.prefix(200))"
            )
        }
    }

    @Test("read_sample success: title + 'Project ID' + 'Description' + 'Metadata' + 'README' sections all present")
    func readSampleSuccessSections() async throws {
        let (provider, cleanup) = try await Self.makeProvider { db in
            try await Self.seedProject(
                on: db,
                id: "animation-sample",
                title: "Animation Sample Project",
                frameworks: ["SwiftUI"]
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "project_id": MCP.Core.Protocols.AnyCodable("animation-sample"),
        ]
        let result = try await provider.callTool(name: "read_sample", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        // Title pulled from project title.
        #expect(
            t.text.contains("# Animation Sample Project"),
            "title header missing — body: \(t.text.prefix(300))"
        )
        // Project ID marker.
        #expect(t.text.contains("**Project ID:**"))
        #expect(t.text.contains("`animation-sample`"))
        // Section headers.
        #expect(t.text.contains("## Description"))
        #expect(t.text.contains("## Metadata"))
        #expect(t.text.contains("## README"))
        // Metadata items.
        #expect(t.text.contains("**Frameworks:**"))
        #expect(t.text.contains("**Files:**"))
        // Negative — must NOT be the not-found error frame.
        #expect(!t.text.contains("Project not found"))
    }

    // MARK: - read_sample_file

    @Test("read_sample_file: missing project_id arg throws ToolError")
    func readSampleFileMissingProjectArg() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "file_path": MCP.Core.Protocols.AnyCodable("ContentView.swift"),
        ]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "read_sample_file", arguments: args)
        }
    }

    @Test("read_sample_file: missing file_path arg throws ToolError")
    func readSampleFileMissingFileArg() async throws {
        let (provider, cleanup) = try await Self.makeProvider { _ in }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "project_id": MCP.Core.Protocols.AnyCodable("animation-sample"),
        ]
        await #expect(throws: Error.self) {
            _ = try await provider.callTool(name: "read_sample_file", arguments: args)
        }
    }

    @Test("read_sample_file: not-found file throws ToolError with 'File not found'")
    func readSampleFileNotFoundThrows() async throws {
        let (provider, cleanup) = try await Self.makeProvider { db in
            try await Self.seedProject(
                on: db,
                id: "animation-sample",
                title: "Animation Sample",
                frameworks: ["SwiftUI"]
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "project_id": MCP.Core.Protocols.AnyCodable("animation-sample"),
            "file_path": MCP.Core.Protocols.AnyCodable("Nonexistent.swift"),
        ]
        do {
            _ = try await provider.callTool(name: "read_sample_file", arguments: args)
            Issue.record("expected throw")
        } catch {
            let desc = "\(error)"
            #expect(
                desc.contains("File not found") || desc.contains("not found"),
                "not-found error must carry marker — got: \(desc.prefix(200))"
            )
        }
    }

    @Test("read_sample_file success: '# <filename>' header + 'Project:' + 'Path:' markers + content fence")
    func readSampleFileSuccess() async throws {
        let fileContent = "import SwiftUI\n\nstruct ContentView: View { var body: some View { Text(\"Hi\") } }"
        let (provider, cleanup) = try await Self.makeProvider { db in
            try await Self.seedProject(
                on: db,
                id: "animation-sample",
                title: "Animation Sample",
                frameworks: ["SwiftUI"]
            )
            try await Self.seedFile(
                on: db,
                projectId: "animation-sample",
                path: "ContentView.swift",
                content: fileContent
            )
        }
        defer { cleanup() }
        let args: [String: MCP.Core.Protocols.AnyCodable] = [
            "project_id": MCP.Core.Protocols.AnyCodable("animation-sample"),
            "file_path": MCP.Core.Protocols.AnyCodable("ContentView.swift"),
        ]
        let result = try await provider.callTool(name: "read_sample_file", arguments: args)
        guard case let .text(t) = result.content.first else { Issue.record("expected text"); return }
        // Filename header.
        #expect(
            t.text.contains("# ContentView.swift"),
            "filename header missing — body: \(t.text.prefix(300))"
        )
        // Project + path markers.
        #expect(t.text.contains("**Project:**"))
        #expect(t.text.contains("`animation-sample`"))
        #expect(t.text.contains("**Path:**"))
        #expect(t.text.contains("`ContentView.swift`"))
        // Fenced code block with content.
        #expect(
            t.text.contains("```swift"),
            "Swift code fence missing — body: \(t.text.prefix(400))"
        )
        #expect(
            t.text.contains("ContentView"),
            "file content must appear in the fence"
        )
        // Negative: not the error frame.
        #expect(!t.text.contains("File not found"))
    }

    // MARK: - Cross-tool title-distinctness regression guard

    @Test("titles are distinct across the 3 sample tools")
    func titlesAreDistinct() async throws {
        let (provider, cleanup) = try await Self.makeProvider { db in
            try await Self.seedProject(
                on: db,
                id: "test-proj",
                title: "TestProj",
                frameworks: ["SwiftUI"]
            )
            try await Self.seedFile(
                on: db,
                projectId: "test-proj",
                path: "File.swift",
                content: "// hello"
            )
        }
        defer { cleanup() }

        let list = try await provider.callTool(name: "list_samples", arguments: [:])
        let read = try await provider.callTool(
            name: "read_sample",
            arguments: ["project_id": MCP.Core.Protocols.AnyCodable("test-proj")]
        )
        let readFile = try await provider.callTool(
            name: "read_sample_file",
            arguments: [
                "project_id": MCP.Core.Protocols.AnyCodable("test-proj"),
                "file_path": MCP.Core.Protocols.AnyCodable("File.swift"),
            ]
        )

        guard case let .text(l) = list.content.first,
              case let .text(r) = read.content.first,
              case let .text(rf) = readFile.content.first
        else { Issue.record("expected text on all 3"); return }

        #expect(l.text.contains("# Indexed Sample Code Projects"))
        #expect(!l.text.contains("# TestProj"))
        #expect(!l.text.contains("# File.swift"))

        #expect(r.text.contains("# TestProj"))
        #expect(!r.text.contains("# Indexed Sample Code Projects"))
        #expect(!r.text.contains("# File.swift"))

        #expect(rf.text.contains("# File.swift"))
        #expect(!rf.text.contains("# Indexed Sample Code Projects"))
        #expect(!rf.text.contains("# TestProj"))
    }
}
