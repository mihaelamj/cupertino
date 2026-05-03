import Foundation
@testable import Ingest
@testable import Shared
import Testing

// MARK: - Ingest.Session smoke tests (#247 sub-PR 4a)

// The full behavioural coverage for the lifted helpers lives in
// `Tests/CLICommandTests/FetchTests/ResumeTests.swift` (CLI-shaped
// integration tests). These suites exist so the Ingest package has its
// own unit-level coverage and so SPM stops warning about an empty
// Tests/IngestTests directory.

@Suite("Ingest.Session.clearSavedSession")
struct ClearSavedSessionSmokeTests {
    @Test("No-op when metadata.json doesn't exist")
    func noopWithoutMetadata() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingest-clear-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Should not throw.
        try Ingest.Session.clearSavedSession(at: dir)

        // Should not have created metadata.json as a side effect.
        let metadataFile = dir.appendingPathComponent(Shared.Constants.FileName.metadata)
        #expect(!FileManager.default.fileExists(atPath: metadataFile.path))
    }
}

@Suite("Ingest.Session.checkForSession")
struct CheckForSessionSmokeTests {
    @Test("Returns nil when directory has no metadata.json")
    func nilWhenNoMetadata() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingest-check-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = URL(string: "https://example.com/")!
        #expect(Ingest.Session.checkForSession(at: dir, matching: url) == nil)
    }
}

@Suite("Ingest.Session internal helpers")
struct SessionInternalHelpersTests {
    @Test("lowercaseDocPath lowercases only the /documentation/ tail")
    func lowercaseDocPathPreservesPrefix() {
        let url = "https://developer.apple.com/documentation/SwiftUI/View"
        #expect(
            Ingest.Session.lowercaseDocPath(url)
                == "https://developer.apple.com/documentation/swiftui/view"
        )
    }

    @Test("lowercaseDocPath falls back to whole-string lowercase when no /documentation/")
    func lowercaseDocPathNoMarker() {
        let url = "https://example.com/Other/Path"
        #expect(Ingest.Session.lowercaseDocPath(url) == "https://example.com/other/path")
    }
}

@Suite("Ingest.FetchURLsError")
struct FetchURLsErrorTests {
    @Test("invalidURL description includes the offending line")
    func invalidURLDescription() {
        let error = Ingest.FetchURLsError.invalidURL(line: "not a url")
        #expect(error.description.contains("not a url"))
    }
}
