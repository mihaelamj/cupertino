@testable import ASTIndexer
import Foundation
import Testing

// MARK: - ASTIndexer Public API Smoke Tests

// ASTIndexer is one of the cleanest packages in the codebase: zero
// internal cupertino deps. It imports Foundation + SwiftSyntax +
// SwiftParser only, and produces an offline AST extraction over Swift
// source code that downstream packages (Search.Index, SampleIndex)
// persist into their FTS5 tables.
//
// Per #391 independence acceptance: ASTIndexer imports only Foundation
// + SwiftSyntax + SwiftParser. No cupertino-internal imports.
// `grep -rln "^import " Packages/Sources/ASTIndexer/` returns exactly
// those three.
//
// Also part of this leaf: the ASTIndexer test target had bloated deps
// ["ASTIndexer", "Search", "SampleIndex", "TestSupport"] because the
// SymbolDatabaseIntegrationTests file lived here. That file has been
// moved to SearchTests/ where the Search.Index + SampleIndex
// integration boundary actually lives, and the ASTIndexerTests deps
// slimmed to ["ASTIndexer", "TestSupport"].
//
// Coverage left in ASTIndexerTests now:
// - DemoExtractionTest (existing) — visual extractor sanity
// - SwiftSourceExtractorTests (existing) — extractor behavioural cases
// - this file — public-surface contract tests against the symbol model

@Suite("ASTIndexer public surface")
struct ASTIndexerPublicSurfaceTests {
    // MARK: Namespace

    @Test("ASTIndexer namespace is reachable and exposes a schema version")
    func namespaceAndSchemaVersion() {
        _ = ASTIndexer.self
        // The schema version backs both search.db and samples.db AST
        // table layouts; consumers gate migrations against it. Pin so
        // accidental bumps land deliberately.
        #expect(ASTIndexer.schemaVersion == 1)
    }

    // MARK: SymbolKind raw values

    @Test("ASTIndexer.SymbolKind raw values are stable")
    func symbolKindRawValues() {
        // The String raw values back the on-disk `kind` column in the
        // doc_symbols / sample_symbols FTS5 tables; renaming any case
        // silently invalidates every indexed symbol. Pin all 16.
        let expected: [ASTIndexer.SymbolKind: String] = [
            .class: "class",
            .struct: "struct",
            .enum: "enum",
            .actor: "actor",
            .protocol: "protocol",
            .extension: "extension",
            .function: "function",
            .method: "method",
            .initializer: "initializer",
            .property: "property",
            .subscript: "subscript",
            .typealias: "typealias",
            .associatedtype: "associatedtype",
            .case: "case",
            .operator: "operator",
            .macro: "macro",
        ]
        for (kind, raw) in expected {
            #expect(kind.rawValue == raw)
        }
        #expect(ASTIndexer.SymbolKind.allCases.count == expected.count)
    }

    // MARK: Symbol / Import / Result shape

    @Test("ASTIndexer.Symbol init exposes every public field")
    func symbolInit() {
        // Full-field init pins the public surface so a refactor that
        // drops genericParameters or attributes will fail to compile
        // the test. Consumers persist all of these into FTS5.
        let symbol = ASTIndexer.Symbol(
            name: "View",
            kind: .protocol,
            line: 10,
            column: 4,
            signature: "protocol View",
            isAsync: false,
            isThrows: false,
            isPublic: true,
            isStatic: false,
            attributes: ["@MainActor"],
            conformances: [],
            genericParameters: []
        )
        #expect(symbol.name == "View")
        #expect(symbol.kind == .protocol)
        #expect(symbol.line == 10)
        #expect(symbol.column == 4)
        #expect(symbol.signature == "protocol View")
        #expect(symbol.isAsync == false)
        #expect(symbol.isThrows == false)
        #expect(symbol.isPublic == true)
        #expect(symbol.isStatic == false)
        #expect(symbol.attributes == ["@MainActor"])
        #expect(symbol.conformances == [])
        #expect(symbol.genericParameters == [])
    }

    @Test("ASTIndexer.Import init exposes every public field")
    func importInit() {
        let imp = ASTIndexer.Import(moduleName: "SwiftUI", line: 1, isExported: false)
        #expect(imp.moduleName == "SwiftUI")
        #expect(imp.line == 1)
        #expect(imp.isExported == false)
    }

    @Test("ASTIndexer.Import default isExported is false")
    func importDefaultIsExported() {
        // @_exported imports get a true; the default for plain
        // `import Foo` must stay false so consumers don't accidentally
        // mark every import as re-exported.
        let imp = ASTIndexer.Import(moduleName: "Foundation", line: 1)
        #expect(imp.isExported == false)
    }

    @Test("ASTIndexer.Result.empty is the failure sentinel")
    func resultEmpty() {
        let empty = ASTIndexer.Result.empty
        #expect(empty.symbols.isEmpty)
        #expect(empty.imports.isEmpty)
        #expect(empty.hasErrors == true)
    }

    // MARK: Extractor

    @Test("ASTIndexer.Extractor extracts the top-level types from a snippet")
    func extractorOnSnippet() {
        let source = """
        import Foundation

        public protocol View {}

        public actor Loader {
            public func fetch() async throws -> [String] { [] }
        }
        """
        let result = ASTIndexer.Extractor().extract(from: source)
        #expect(result.hasErrors == false)
        // Don't over-pin SwiftSyntax's exact emission shape; verify
        // semantic claims instead (protocol named View, actor named
        // Loader, an Foundation import row).
        let kinds = Set(result.symbols.map(\.kind))
        #expect(kinds.contains(.protocol))
        #expect(kinds.contains(.actor))
        #expect(result.symbols.contains(where: { $0.name == "View" }))
        #expect(result.symbols.contains(where: { $0.name == "Loader" }))
        #expect(result.imports.contains(where: { $0.moduleName == "Foundation" }))
    }
}
