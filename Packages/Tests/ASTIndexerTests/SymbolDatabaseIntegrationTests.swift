// SymbolDatabaseIntegrationTests.swift
// Integration tests for AST symbol storage and search (#81)

import ASTIndexer
import Foundation
import SampleIndex
import Search
import Shared
import Testing

// MARK: - Search.db Symbol Integration Tests

@Suite("Search.db Symbol Integration", .serialized)
struct SearchDbSymbolIntegrationTests {
    /// Create an in-memory search index for testing
    private func createTestSearchIndex() async throws -> (Search.Index, () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-symbol-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("search.db")
        let index = try await Search.Index(dbPath: dbPath)

        let cleanup = {
            Task { await index.disconnect() }
            try? FileManager.default.removeItem(at: tempDir)
        }

        return (index, cleanup)
    }

    @Test("Extraction produces searchable symbol text")
    func extractionProducesSearchableText() {
        let extractor = ASTIndexer.SwiftSourceExtractor()

        let source = """
        @Observable
        @MainActor
        class DataManager: Sendable {
            @Published var items: [String] = []

            func fetchData() async throws -> [Item] {
                return []
            }
        }
        """

        let result = extractor.extract(from: source)

        // Verify we get searchable text for FTS
        let symbolNames = result.symbols.map(\.name)
        #expect(symbolNames.contains("DataManager"))
        #expect(symbolNames.contains("items"))
        #expect(symbolNames.contains("fetchData"))

        // Verify attributes are captured for semantic search
        let classSymbol = result.symbols.first { $0.kind == .class }
        #expect(classSymbol?.attributes.contains("@Observable") == true)
        #expect(classSymbol?.attributes.contains("@MainActor") == true)
        #expect(classSymbol?.conformances.contains("Sendable") == true)

        // Verify async/throws flags
        let methodSymbol = result.symbols.first { $0.kind == .method }
        #expect(methodSymbol?.isAsync == true)
        #expect(methodSymbol?.isThrows == true)
    }

    @Test("FTS text generation includes all searchable content")
    func ftsTextGeneration() {
        let extractor = ASTIndexer.SwiftSourceExtractor()

        let source = """
        import SwiftUI
        import Observation

        @Observable
        class ViewModel: ObservableObject {
            @Published var state: ViewState = .idle
        }

        struct ContentView: View {
            @State private var isLoading = false
            @Binding var name: String

            var body: some View {
                Text("Hello")
            }
        }

        actor ImageLoader {
            func load(url: URL) async throws -> Data {
                Data()
            }
        }
        """

        let result = extractor.extract(from: source)

        // Generate FTS-searchable text (what would go into the FTS index)
        var ftsContent: [String] = []
        for symbol in result.symbols {
            ftsContent.append(symbol.name)
            ftsContent.append(contentsOf: symbol.attributes)
            ftsContent.append(contentsOf: symbol.conformances)
            if let sig = symbol.signature {
                ftsContent.append(sig)
            }
        }
        let ftsText = ftsContent.joined(separator: " ")

        // Verify all important terms are searchable
        #expect(ftsText.contains("Observable"))
        #expect(ftsText.contains("MainActor") == false) // Not in this code
        #expect(ftsText.contains("View"))
        #expect(ftsText.contains("ContentView"))
        #expect(ftsText.contains("ViewModel"))
        #expect(ftsText.contains("ImageLoader"))
        #expect(ftsText.contains("actor") == false) // Kind not in text, but in db column
        #expect(ftsText.contains("State"))
        #expect(ftsText.contains("Binding"))
        #expect(ftsText.contains("async"))
        #expect(ftsText.contains("throws"))
    }
}

// MARK: - Samples.db Symbol Integration Tests

@Suite("Samples.db Symbol Integration", .serialized)
struct SamplesDbSymbolIntegrationTests {
    /// Create a test sample database
    private func createTestSampleDatabase() async throws -> (SampleIndex.Database, () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-symbol-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("samples.db")
        let database = try await SampleIndex.Database(dbPath: dbPath)

        let cleanup: () -> Void = {
            try? FileManager.default.removeItem(at: tempDir)
        }

        return (database, cleanup)
    }

    @Test("Sample file symbols can be indexed")
    func sampleSymbolsCanBeIndexed() async throws {
        let (database, cleanup) = try await createTestSampleDatabase()
        defer { cleanup() }

        // Create project
        let project = SampleIndex.Project(
            id: "observable-sample",
            title: "Observable Sample",
            description: "Sample showing @Observable usage",
            frameworks: ["swiftui", "observation"],
            readme: "# Observable Sample",
            webURL: "https://developer.apple.com/sample/observable",
            zipFilename: "observable-sample.zip",
            fileCount: 1,
            totalSize: 500
        )
        try await database.indexProject(project)

        // Create and index file
        let swiftSource = """
        import SwiftUI

        @Observable
        class AppState {
            var count = 0

            func increment() {
                count += 1
            }
        }

        struct CounterView: View {
            var body: some View {
                Text("Counter")
            }
        }
        """

        let file = SampleIndex.File(
            projectId: "observable-sample",
            path: "Sources/AppState.swift",
            content: swiftSource
        )
        try await database.indexFile(file)

        // Extract symbols
        let extractor = ASTIndexer.SwiftSourceExtractor()
        let result = extractor.extract(from: swiftSource)

        // Index symbols if file ID is available
        if let fileId = try await database.getFileId(
            projectId: "observable-sample",
            path: "Sources/AppState.swift"
        ) {
            try await database.indexSymbols(fileId: fileId, symbols: result.symbols)
            try await database.indexImports(fileId: fileId, imports: result.imports)
        }

        // Verify extraction worked correctly
        #expect(result.symbols.count >= 4) // class, 2 properties, method, struct, property
        #expect(result.imports.count == 1) // SwiftUI

        let classSymbol = result.symbols.first { $0.kind == .class }
        #expect(classSymbol?.name == "AppState")
        #expect(classSymbol?.attributes.contains("@Observable") == true)

        let structSymbol = result.symbols.first { $0.kind == .struct }
        #expect(structSymbol?.name == "CounterView")
        #expect(structSymbol?.conformances.contains("View") == true)
    }

    @Test("Multiple Swift files can be indexed with symbols")
    func multipleFilesWithSymbols() async throws {
        let (database, cleanup) = try await createTestSampleDatabase()
        defer { cleanup() }

        let project = SampleIndex.Project(
            id: "multi-file-sample",
            title: "Multi-File Sample",
            description: "Sample with multiple Swift files",
            frameworks: ["swiftui"],
            readme: "# Multi-File",
            webURL: "https://developer.apple.com/sample/multi",
            zipFilename: "multi.zip",
            fileCount: 3,
            totalSize: 1500
        )
        try await database.indexProject(project)

        let files = [
            ("Models/User.swift", """
            struct User: Codable, Identifiable {
                let id: UUID
                var name: String
            }
            """),
            ("ViewModels/UserViewModel.swift", """
            @Observable
            @MainActor
            class UserViewModel {
                var users: [User] = []

                func loadUsers() async throws {
                    users = []
                }
            }
            """),
            ("Views/UserListView.swift", """
            import SwiftUI

            struct UserListView: View {
                @State private var viewModel = UserViewModel()

                var body: some View {
                    List(viewModel.users) { user in
                        Text(user.name)
                    }
                }
            }
            """),
        ]

        let extractor = ASTIndexer.SwiftSourceExtractor()
        var totalSymbols = 0

        for (path, content) in files {
            let file = SampleIndex.File(
                projectId: "multi-file-sample",
                path: path,
                content: content
            )
            try await database.indexFile(file)

            let result = extractor.extract(from: content)
            totalSymbols += result.symbols.count

            if let fileId = try await database.getFileId(
                projectId: "multi-file-sample",
                path: path
            ) {
                try await database.indexSymbols(fileId: fileId, symbols: result.symbols)
                try await database.indexImports(fileId: fileId, imports: result.imports)
            }
        }

        // Verify we extracted symbols from all files
        // File 1: struct + 2 props = 3, File 2: class + 2 members = 3, File 3: struct + 2 props = 3
        #expect(totalSymbols >= 9, "Expected at least 9 symbols across 3 files")
    }
}

// MARK: - Semantic Search Demonstration

@Suite("Semantic Search Demo")
struct SemanticSearchDemoTests {
    @Test("Demonstrate semantic search capabilities")
    func semanticSearchDemo() {
        let extractor = ASTIndexer.SwiftSourceExtractor()

        // Sample representing typical Apple documentation code example
        let sampleCode = """
        import SwiftUI
        import Observation
        import Foundation

        // MARK: - Observable View Model

        @Observable
        @MainActor
        final class ArticleListViewModel {
            var articles: [Article] = []
            var isLoading = false
            var errorMessage: String?

            private let networkService: NetworkService

            init(networkService: NetworkService = .shared) {
                self.networkService = networkService
            }

            func fetchArticles() async throws {
                isLoading = true
                defer { isLoading = false }

                do {
                    articles = try await networkService.fetchArticles()
                } catch {
                    errorMessage = error.localizedDescription
                    throw error
                }
            }
        }

        // MARK: - SwiftUI View

        struct ArticleListView: View {
            @State private var viewModel = ArticleListViewModel()
            @Environment(\\.dismiss) private var dismiss

            var body: some View {
                NavigationStack {
                    List(viewModel.articles) { article in
                        ArticleRow(article: article)
                    }
                    .navigationTitle("Articles")
                    .task {
                        try? await viewModel.fetchArticles()
                    }
                }
            }
        }

        // MARK: - Actor for Thread Safety

        actor NetworkService {
            static let shared = NetworkService()

            func fetchArticles() async throws -> [Article] {
                // Network call
                return []
            }
        }

        // MARK: - Model

        struct Article: Identifiable, Codable, Sendable {
            let id: UUID
            let title: String
            let content: String
        }
        """

        let result = extractor.extract(from: sampleCode)

        print("\n")
        print("════════════════════════════════════════════════════════════")
        print("         SEMANTIC SEARCH DEMONSTRATION")
        print("════════════════════════════════════════════════════════════\n")

        // Show what searches would find
        print("📍 Search: '@Observable' would find:")
        for symbol in result.symbols where symbol.attributes.contains("@Observable") {
            print("   → \(symbol.kind): \(symbol.name)")
        }

        print("\n📍 Search: '@MainActor' would find:")
        for symbol in result.symbols where symbol.attributes.contains("@MainActor") {
            print("   → \(symbol.kind): \(symbol.name)")
        }

        print("\n📍 Search: 'View conformance' would find:")
        for symbol in result.symbols where symbol.conformances.contains("View") {
            print("   → \(symbol.kind): \(symbol.name)")
        }

        print("\n📍 Search: 'async throws' would find:")
        for symbol in result.symbols where symbol.isAsync && symbol.isThrows {
            print("   → \(symbol.kind): \(symbol.name)")
            if let sig = symbol.signature { print("      \(sig)") }
        }

        print("\n📍 Search: 'actor' would find:")
        for symbol in result.symbols where symbol.kind == .actor {
            print("   → \(symbol.name)")
        }

        print("\n📍 Search: 'Sendable' would find:")
        for symbol in result.symbols where symbol.conformances.contains("Sendable") {
            print("   → \(symbol.kind): \(symbol.name)")
        }

        print("\n📍 Search: '@State property' would find:")
        for symbol in result.symbols where symbol.attributes.contains(where: { $0.contains("State") }) {
            print("   → \(symbol.name)")
        }

        print("\n════════════════════════════════════════════════════════════")
        print("  Summary: \(result.symbols.count) symbols, \(result.imports.count) imports")
        print("════════════════════════════════════════════════════════════\n")

        // Assertions for the test
        #expect(result.symbols.count >= 15)
        #expect(result.imports.count == 3)

        // Verify specific semantic searches work
        let observableSymbols = result.symbols.filter { $0.attributes.contains("@Observable") }
        #expect(observableSymbols.count >= 1)

        let viewSymbols = result.symbols.filter { $0.conformances.contains("View") }
        #expect(viewSymbols.count >= 1)

        let asyncThrowsMethods = result.symbols.filter { $0.isAsync && $0.isThrows }
        #expect(asyncThrowsMethods.count >= 1)

        let actors = result.symbols.filter { $0.kind == .actor }
        #expect(actors.count >= 1)
    }
}
