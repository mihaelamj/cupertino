import Foundation
@testable import SampleIndexModels
import SharedConstants
import Testing

// Smoke tests for the SampleIndexModels target. Pin the public namespace
// surface so accidental renames or accidental cross-target imports fail
// fast in CI rather than at downstream-build time. Equivalent in spirit
// to SearchModelsTests — minimal coverage, just enough to verify the
// types are visible, Sendable, Codable where claimed, and shaped the
// way `Sample.Index.Reader` callers expect.

@Suite("SampleIndexModels public surface")
struct SampleIndexModelsTests {
    // MARK: - Sample.Index.Project

    @Test("Sample.Index.Project round-trips through JSON")
    func projectRoundTrip() throws {
        let original = Sample.Index.Project(
            id: "swiftui-essentials",
            title: "SwiftUI Essentials",
            description: "Learn SwiftUI by building real apps.",
            frameworks: ["swiftui", "foundation"],
            readme: "# SwiftUI Essentials\n…",
            webURL: "https://developer.apple.com/sample/swiftui-essentials",
            zipFilename: "swiftui-essentials.zip",
            fileCount: 42,
            totalSize: 1_234_567,
            indexedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deploymentTargets: ["ios": "17.0", "macos": "14.0"],
            availabilitySource: "sample-swift"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Sample.Index.Project.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.frameworks == ["swiftui", "foundation"])
        #expect(decoded.deploymentTargets["ios"] == "17.0")
    }

    @Test("Project lowercases framework names on init")
    func projectLowercasesFrameworks() {
        let project = Sample.Index.Project(
            id: "x", title: "X", description: "",
            frameworks: ["SwiftUI", "Foundation"],
            readme: nil, webURL: "", zipFilename: "",
            fileCount: 0, totalSize: 0
        )
        #expect(project.frameworks == ["swiftui", "foundation"])
    }

    // MARK: - Sample.Index.File

    @Test("File derives filename, folder, extension from path")
    func fileDerivesPathComponents() {
        let file = Sample.Index.File(
            projectId: "p",
            path: "Sources/Views/ContentView.swift",
            content: "import SwiftUI\nstruct ContentView: View {}\n"
        )

        #expect(file.filename == "ContentView.swift")
        #expect(file.folder == "Sources/Views")
        #expect(file.fileExtension == "swift")
        #expect(file.size == file.content.utf8.count)
    }

    @Test("File at repo root has empty folder")
    func fileAtRootHasEmptyFolder() {
        let file = Sample.Index.File(
            projectId: "p",
            path: "README.md",
            content: "# Hi"
        )
        #expect(file.filename == "README.md")
        #expect(file.folder == "")
        #expect(file.fileExtension == "md")
    }

    @Test("File.shouldIndex respects indexableExtensions")
    func shouldIndexExtensions() {
        #expect(Sample.Index.shouldIndex(path: "x.swift"))
        #expect(Sample.Index.shouldIndex(path: "Path/To/x.h"))
        #expect(Sample.Index.shouldIndex(path: "README.md"))
        #expect(!Sample.Index.shouldIndex(path: "binary.dll"))
        #expect(!Sample.Index.shouldIndex(path: "image.png"))
    }

    // MARK: - Sample.Index.FileSearchResult

    @Test("FileSearchResult holds the five public fields")
    func fileSearchResultFields() {
        let hit = Sample.Index.FileSearchResult(
            projectId: "p",
            path: "Sources/View.swift",
            filename: "View.swift",
            snippet: "struct V: View { … }",
            rank: -3.14
        )
        #expect(hit.projectId == "p")
        #expect(hit.path == "Sources/View.swift")
        #expect(hit.filename == "View.swift")
        #expect(hit.snippet == "struct V: View { … }")
        #expect(hit.rank == -3.14)
    }

    // MARK: - Sample.Index.Reader (existence + shape)

    @Test("Sample.Index.Reader is reachable as a protocol type")
    func readerProtocolIsReachable() {
        // Compile-time check: the protocol can be used as an existential.
        // If the protocol got renamed or moved, this stops compiling.
        let optionalReader: (any Sample.Index.Reader)? = nil
        #expect(optionalReader == nil)
    }
}
