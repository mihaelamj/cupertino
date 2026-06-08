import ASTIndexer
import Foundation
import LoggingModels
import MCPCore
@testable import SampleIndex
import SampleIndexSQLite
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
@testable import SearchToolProvider
import SharedConstants
import Testing

enum Issue1260TypedMCPOutputFixtures {
    static func makeSearchProvider(
        seed: (Search.Index) async throws -> Void
    ) async throws -> (provider: CompositeToolProvider, cleanup: () -> Void) {
        let tempDir = tempBaseDir()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        try await seed(index)
        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: nil)
        return (provider, {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: tempDir)
        })
    }

    static func makeSampleProvider(
        seed: (Sample.Index.Database) async throws -> Void
    ) async throws -> (provider: CompositeToolProvider, cleanup: () -> Void) {
        let tempDir = tempBaseDir()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("samples.db")
        let database = try await Sample.Index.Database(dbPath: dbPath, logger: Logging.NoopRecording())
        try await seed(database)
        let provider = CompositeToolProvider(searchIndex: nil, sampleDatabase: database)
        return (provider, {
            Task { await database.disconnect() }
            try? FileManager.default.removeItem(at: tempDir)
        })
    }

    static func makeFullProvider(
        seedSearch: (Search.Index) async throws -> Void,
        seedSample: (Sample.Index.Database) async throws -> Void
    ) async throws -> (provider: CompositeToolProvider, cleanup: () -> Void) {
        let tempDir = tempBaseDir()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let searchPath = tempDir.appendingPathComponent("search.db")
        let samplesPath = tempDir.appendingPathComponent("samples.db")
        let index = try await Search.Index(dbPath: searchPath, logger: Logging.NoopRecording(), indexers: [:], sourceLookup: .empty)
        let database = try await Sample.Index.Database(dbPath: samplesPath, logger: Logging.NoopRecording())
        try await seedSearch(index)
        try await seedSample(database)
        let provider = CompositeToolProvider(searchIndex: index, sampleDatabase: database)
        return (provider, {
            Task {
                await index.disconnect()
                await database.disconnect()
            }
            try? FileManager.default.removeItem(at: tempDir)
        })
    }

    static func jsonObject(
        from result: MCP.Core.Protocols.CallToolResult
    ) throws -> [String: Any] {
        guard case let .text(text) = result.content.first else {
            Issue.record("expected text JSON content")
            return [:]
        }
        let data = Data(text.text.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    static func jsonArgs(_ pairs: (String, String)...) -> [String: MCP.Core.Protocols.AnyCodable] {
        Dictionary(uniqueKeysWithValues: pairs.map { key, value in
            (key, MCP.Core.Protocols.AnyCodable(value))
        })
    }

    static func seedProjectAndFile(on database: Sample.Index.Database) async throws {
        try await database.indexProject(Sample.Index.Project(
            id: "cupertino-demo",
            title: "Cupertino Demo",
            description: "Sample for typed output.",
            frameworks: ["SwiftUI", "UIKit"],
            readme: "# Cupertino Demo\n\nReadme.",
            webURL: "https://developer.apple.com/documentation/samplecode/cupertino-demo",
            zipFilename: "cupertino-demo.zip",
            fileCount: 1,
            totalSize: 38,
            deploymentTargets: ["ios": "17.0"],
            availabilitySource: "sample-swift"
        ))
        try await database.indexFile(Sample.Index.File(
            projectId: "cupertino-demo",
            path: "Sources/ContentView.swift",
            content: "import SwiftUI\nstruct ContentView {}\n"
        ))
    }

    static func seedDocument(
        on index: Search.Index,
        uri: String,
        framework: String,
        title: String
    ) async throws {
        try await index.indexDocument(Search.IndexDocumentParams(
            uri: uri,
            source: Shared.Constants.SourcePrefix.appleDocs,
            framework: framework,
            title: title,
            content: "Documentation for \(title).",
            filePath: "/tmp/\(title)-\(UUID().uuidString).json",
            contentHash: "hash-\(UUID().uuidString.prefix(8))",
            lastCrawled: Date()
        ))
    }

    static func seedSymbols(on index: Search.Index) async throws {
        let uri = "apple-docs://swiftui/typedbox"
        try await seedDocument(on: index, uri: uri, framework: "swiftui", title: "TypedBox")
        let symbols = [
            ASTIndexer.Symbol(
                name: "TypedBox",
                kind: .struct,
                line: 1,
                column: 1,
                signature: "struct TypedBox<T: Sendable>: View",
                isPublic: true,
                attributes: ["@MainActor"],
                conformances: ["View", "Sendable"],
                genericParameters: ["T: Sendable"]
            ),
            ASTIndexer.Symbol(
                name: "loadTypedBox",
                kind: .function,
                line: 2,
                column: 1,
                signature: "func loadTypedBox() async -> TypedBox",
                isAsync: true,
                isPublic: true
            ),
        ]
        try await index.indexDocSymbols(docUri: uri, symbols: symbols)
    }

    private static func tempBaseDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("issue1260-\(UUID().uuidString)")
    }
}
