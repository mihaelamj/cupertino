// DemoExtractionTest.swift
// Demo test to show extraction output

import ASTIndexer
import Testing

@Suite("Demo Extraction")
struct DemoExtractionTest {
    @Test("Show extraction output")
    func showExtractionOutput() {
        let source = """
        import SwiftUI
        import Foundation

        @Observable
        @MainActor
        class AppState {
            @Published var items: [String] = []
            private var cache: [String: Data] = [:]

            func fetchItems() async throws -> [String] {
                return []
            }

            static func shared() -> AppState {
                AppState()
            }
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

        enum Status: String, Codable, Sendable {
            case pending
            case active
            case done
        }

        extension String: Identifiable {
            var id: String { self }
        }
        """

        let extractor = ASTIndexer.Extractor()
        let result = extractor.extract(from: source)

        print("\n")
        print("═══════════════════════════════════════════════════════════════")
        print("                    AST EXTRACTION RESULTS")
        print("═══════════════════════════════════════════════════════════════")

        print("\n📦 IMPORTS (\(result.imports.count))")
        print("───────────────────────────────────────────────────────────────")
        for imp in result.imports {
            print("  • \(imp.moduleName) (line \(imp.line))")
        }

        print("\n🏗️  SYMBOLS (\(result.symbols.count))")
        print("───────────────────────────────────────────────────────────────")
        for symbol in result.symbols {
            var line = "  [\(symbol.kind)] \(symbol.name)"
            line += " @ line \(symbol.line)"

            if !symbol.attributes.isEmpty {
                print(line)
                print("      attributes: \(symbol.attributes.joined(separator: ", "))")
            } else if !symbol.conformances.isEmpty {
                print(line)
            } else {
                print(line)
            }

            if !symbol.conformances.isEmpty {
                print("      conforms to: \(symbol.conformances.joined(separator: ", "))")
            }

            var flags: [String] = []
            if symbol.isAsync { flags.append("async") }
            if symbol.isThrows { flags.append("throws") }
            if symbol.isStatic { flags.append("static") }
            if symbol.isPublic { flags.append("public") }
            if !flags.isEmpty {
                print("      flags: \(flags.joined(separator: ", "))")
            }

            if let sig = symbol.signature {
                print("      signature: \(sig)")
            }
        }

        print("\n═══════════════════════════════════════════════════════════════")
        print("  Total: \(result.symbols.count) symbols, \(result.imports.count) imports")
        print("  Errors: \(result.hasErrors ? "yes" : "none")")
        print("═══════════════════════════════════════════════════════════════\n")

        #expect(!result.hasErrors)
        #expect(!result.symbols.isEmpty)
    }
}
