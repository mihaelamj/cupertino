// SwiftSourceExtractorTests.swift
// Tests for SwiftSyntax-based symbol extraction (#81)

import ASTIndexer
import Testing

@Suite("SwiftSourceExtractor Tests")
struct SwiftSourceExtractorTests {
    let extractor = ASTIndexer.SwiftSourceExtractor()

    @Test("Extract class declaration")
    func extractClass() {
        let source = """
        @Observable
        class AppState {
            var count = 0
        }
        """
        let result = extractor.extract(from: source)

        #expect(!result.hasErrors)
        #expect(result.symbols.count >= 2) // class + property

        let classSymbol = result.symbols.first { $0.kind == .class }
        #expect(classSymbol?.name == "AppState")
        #expect(classSymbol?.attributes.contains("@Observable") == true)
    }

    @Test("Extract struct with conformances")
    func extractStructWithConformances() {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        let result = extractor.extract(from: source)

        let structSymbol = result.symbols.first { $0.kind == .struct }
        #expect(structSymbol?.name == "ContentView")
        #expect(structSymbol?.conformances.contains("View") == true)
    }

    @Test("Extract actor declaration")
    func extractActor() {
        let source = """
        actor ImageDownloader {
            func download(url: URL) async throws -> Data {
                fatalError()
            }
        }
        """
        let result = extractor.extract(from: source)

        let actorSymbol = result.symbols.first { $0.kind == .actor }
        #expect(actorSymbol?.name == "ImageDownloader")

        let methodSymbol = result.symbols.first { $0.kind == .method }
        #expect(methodSymbol?.name == "download")
        #expect(methodSymbol?.isAsync == true)
        #expect(methodSymbol?.isThrows == true)
    }

    @Test("Extract async function")
    func extractAsyncFunction() {
        let source = """
        func fetchData() async throws -> [Item] {
            return []
        }
        """
        let result = extractor.extract(from: source)

        let funcSymbol = result.symbols.first { $0.kind == .function }
        #expect(funcSymbol?.name == "fetchData")
        #expect(funcSymbol?.isAsync == true)
        #expect(funcSymbol?.isThrows == true)
        #expect(funcSymbol?.signature?.contains("async") == true)
    }

    @Test("Extract property wrappers")
    func extractPropertyWrappers() {
        let source = """
        struct SettingsView: View {
            @State private var isEnabled = false
            @Binding var name: String
            @Environment(\\.colorScheme) var colorScheme

            var body: some View {
                EmptyView()
            }
        }
        """
        let result = extractor.extract(from: source)

        let properties = result.symbols.filter { $0.kind == .property }
        #expect(properties.count >= 3)

        let stateProperty = properties.first { $0.name == "isEnabled" }
        #expect(stateProperty?.attributes.contains { $0.contains("State") } == true)

        let bindingProperty = properties.first { $0.name == "name" }
        #expect(bindingProperty?.attributes.contains { $0.contains("Binding") } == true)
    }

    @Test("Extract imports")
    func extractImports() {
        let source = """
        import SwiftUI
        import Foundation
        import MapKit

        struct MyView: View {
            var body: some View { EmptyView() }
        }
        """
        let result = extractor.extract(from: source)

        #expect(result.imports.count == 3)
        #expect(result.imports.map(\.moduleName).contains("SwiftUI"))
        #expect(result.imports.map(\.moduleName).contains("Foundation"))
        #expect(result.imports.map(\.moduleName).contains("MapKit"))
    }

    @Test("Extract enum with cases")
    func extractEnum() {
        let source = """
        enum Status: String, Codable {
            case pending
            case active
            case completed
        }
        """
        let result = extractor.extract(from: source)

        let enumSymbol = result.symbols.first { $0.kind == .enum }
        #expect(enumSymbol?.name == "Status")
        #expect(enumSymbol?.conformances.contains("String") == true)
        #expect(enumSymbol?.conformances.contains("Codable") == true)

        let cases = result.symbols.filter { $0.kind == .case }
        #expect(cases.count == 3)
    }

    @Test("Extract protocol")
    func extractProtocol() {
        let source = """
        protocol DataService: Sendable {
            func fetch() async throws -> Data
        }
        """
        let result = extractor.extract(from: source)

        let protocolSymbol = result.symbols.first { $0.kind == .protocol }
        #expect(protocolSymbol?.name == "DataService")
        #expect(protocolSymbol?.conformances.contains("Sendable") == true)
    }

    @Test("Extract MainActor attribute")
    func extractMainActor() {
        let source = """
        @MainActor
        class ViewModel: ObservableObject {
            @Published var items: [String] = []

            func refresh() {
                items = []
            }
        }
        """
        let result = extractor.extract(from: source)

        let classSymbol = result.symbols.first { $0.kind == .class }
        #expect(classSymbol?.attributes.contains("@MainActor") == true)
        #expect(classSymbol?.conformances.contains("ObservableObject") == true)
    }

    @Test("Handle syntax errors gracefully")
    func handleSyntaxErrors() {
        let source = """
        class Incomplete {
            var x =
        """
        let result = extractor.extract(from: source)

        // Should still parse what it can
        #expect(result.hasErrors == true)
        // Should still find the class
        let classSymbol = result.symbols.first { $0.kind == .class }
        #expect(classSymbol?.name == "Incomplete")
    }

    @Test("Extract extension with conformance")
    func extractExtension() {
        let source = """
        extension String: Identifiable {
            var id: String { self }
        }
        """
        let result = extractor.extract(from: source)

        let extensionSymbol = result.symbols.first { $0.kind == .extension }
        #expect(extensionSymbol?.name == "String")
        #expect(extensionSymbol?.conformances.contains("Identifiable") == true)
    }

    @Test("Extract generic type")
    func extractGenericType() {
        let source = """
        struct Container<T: Hashable> {
            var value: T
        }
        """
        let result = extractor.extract(from: source)

        let structSymbol = result.symbols.first { $0.kind == .struct }
        #expect(structSymbol?.name == "Container")
        #expect(structSymbol?.genericParameters.contains("T: Hashable") == true)
    }
}
