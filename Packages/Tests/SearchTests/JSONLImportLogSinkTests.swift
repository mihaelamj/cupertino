import Foundation
@testable import Search
import SearchModels
import Testing

// MARK: - #588 JSONL audit log sink tests

@Suite("Search.JSONLImportLogSink (#588 per-doc audit log)")
struct JSONLImportLogSinkTests {
    @Test("Appends one JSON line per record() call; readable JSONL")
    func appendsJSONLines() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-jsonl-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let logPath = tempDir.appendingPathComponent("save.jsonl")

        let sink = try Search.JSONLImportLogSink(path: logPath)
        await sink.record(Search.ImportLogEntry(
            sourceFile: "/tmp/a.json",
            resolvedURL: "https://developer.apple.com/documentation/swiftui/view",
            uri: "apple-docs://swiftui/view",
            state: .indexed
        ))
        await sink.record(Search.ImportLogEntry(
            sourceFile: "/tmp/b.json",
            resolvedURL: "https://developer.apple.com/documentation/SwiftUI/View",
            uri: "apple-docs://swiftui/view",
            state: .benignDupTierB,
            duplicateOf: "apple-docs://swiftui/view"
        ))
        await sink.close()

        let content = try String(contentsOf: logPath, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)

        // Each line must parse as JSON and round-trip.
        let decoder = JSONDecoder()
        for line in lines {
            let data = Data(line.utf8)
            _ = try decoder.decode(Search.ImportLogEntry.self, from: data)
        }

        // First record is `indexed`.
        let first = try decoder.decode(
            Search.ImportLogEntry.self,
            from: Data(lines[0].utf8)
        )
        #expect(first.state == .indexed)
        #expect(first.uri == "apple-docs://swiftui/view")

        // Second record is `benignDupTierB` with duplicateOf set.
        let second = try decoder.decode(
            Search.ImportLogEntry.self,
            from: Data(lines[1].utf8)
        )
        #expect(second.state == .benignDupTierB)
        #expect(second.duplicateOf == "apple-docs://swiftui/view")
    }

    @Test("Creates parent .cupertino/ directory if missing")
    func createsParentDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-jsonl-mkdir-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Don't create tempDir; sink must mkdir -p the parent.
        let logPath = tempDir
            .appendingPathComponent(".cupertino")
            .appendingPathComponent("save.jsonl")
        let sink = try Search.JSONLImportLogSink(path: logPath)
        await sink.record(Search.ImportLogEntry(
            sourceFile: "/x", resolvedURL: nil, uri: nil, state: .rejectedNoURL
        ))
        await sink.close()

        #expect(FileManager.default.fileExists(atPath: logPath.path))
    }

    @Test("Records survive close() — content flushed to disk")
    func contentFlushedOnClose() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-jsonl-flush-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let logPath = tempDir.appendingPathComponent("save.jsonl")

        let sink = try Search.JSONLImportLogSink(path: logPath)
        for i in 0 ..< 50 {
            await sink.record(Search.ImportLogEntry(
                sourceFile: "/tmp/file\(i).json",
                resolvedURL: "https://developer.apple.com/documentation/test/\(i)",
                uri: "apple-docs://test/\(i)",
                state: .indexed
            ))
        }
        await sink.close()

        let content = try String(contentsOf: logPath, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 50)
    }
}
