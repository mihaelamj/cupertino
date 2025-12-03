import Testing

@testable import SampleIndex

@Suite("SampleIndex Tests")
struct SampleIndexTests {
    @Test("Project ID extraction from filename")
    func projectIdFromFilename() {
        // Test that the File model extracts path components correctly
        let file = SampleIndex.File(
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
        #expect(SampleIndex.shouldIndex(path: "main.swift"))
        #expect(SampleIndex.shouldIndex(path: "ViewController.m"))
        #expect(SampleIndex.shouldIndex(path: "Header.h"))

        // Binary files should not be indexed
        #expect(!SampleIndex.shouldIndex(path: "image.png"))
        #expect(!SampleIndex.shouldIndex(path: "model.usdz"))
        #expect(!SampleIndex.shouldIndex(path: "binary.dat"))
    }

    @Test("Project model creation")
    func projectModel() {
        let project = SampleIndex.Project(
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
