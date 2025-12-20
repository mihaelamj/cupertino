// ExtractedSymbol.swift
// Data models for extracted AST symbols (#81)

import Foundation

extension ASTIndexer {
    /// Kind of Swift symbol
    public enum SymbolKind: String, Codable, Sendable, CaseIterable {
        case `class`
        case `struct`
        case `enum`
        case `actor`
        case `protocol`
        case `extension`
        case function
        case method
        case initializer
        case property
        case `subscript`
        case `typealias`
        case `associatedtype`
        case `case` // enum case
        case `operator`
        case macro
    }

    /// A symbol extracted from Swift source code
    public struct ExtractedSymbol: Codable, Sendable, Hashable {
        /// Symbol name (e.g., "AppState", "fetchItems", "count")
        public let name: String

        /// Kind of symbol
        public let kind: SymbolKind

        /// Line number in source (1-indexed)
        public let line: Int

        /// Column number in source (1-indexed)
        public let column: Int

        /// Full signature for functions/methods (e.g., "func fetchItems() async throws -> [Item]")
        public let signature: String?

        /// Whether the symbol is async
        public let isAsync: Bool

        /// Whether the symbol throws
        public let isThrows: Bool

        /// Whether the symbol is public
        public let isPublic: Bool

        /// Whether the symbol is static
        public let isStatic: Bool

        /// Attributes applied to the symbol (e.g., ["@MainActor", "@Observable"])
        public let attributes: [String]

        /// Protocol conformances (for types)
        public let conformances: [String]

        /// Generic parameters (e.g., ["T", "U: Hashable"])
        public let genericParameters: [String]

        public init(
            name: String,
            kind: SymbolKind,
            line: Int,
            column: Int,
            signature: String? = nil,
            isAsync: Bool = false,
            isThrows: Bool = false,
            isPublic: Bool = false,
            isStatic: Bool = false,
            attributes: [String] = [],
            conformances: [String] = [],
            genericParameters: [String] = []
        ) {
            self.name = name
            self.kind = kind
            self.line = line
            self.column = column
            self.signature = signature
            self.isAsync = isAsync
            self.isThrows = isThrows
            self.isPublic = isPublic
            self.isStatic = isStatic
            self.attributes = attributes
            self.conformances = conformances
            self.genericParameters = genericParameters
        }
    }

    /// An import statement extracted from Swift source
    public struct ExtractedImport: Codable, Sendable, Hashable {
        /// Module name (e.g., "SwiftUI", "Foundation")
        public let moduleName: String

        /// Line number in source
        public let line: Int

        /// Whether this is an @_exported import
        public let isExported: Bool

        public init(moduleName: String, line: Int, isExported: Bool = false) {
            self.moduleName = moduleName
            self.line = line
            self.isExported = isExported
        }
    }

    /// Result of parsing a Swift source file
    public struct ExtractionResult: Codable, Sendable {
        /// All symbols found in the source
        public let symbols: [ExtractedSymbol]

        /// All imports found in the source
        public let imports: [ExtractedImport]

        /// Whether the source had syntax errors
        public let hasErrors: Bool

        /// Error message if parsing failed completely
        public let errorMessage: String?

        public init(
            symbols: [ExtractedSymbol],
            imports: [ExtractedImport],
            hasErrors: Bool = false,
            errorMessage: String? = nil
        ) {
            self.symbols = symbols
            self.imports = imports
            self.hasErrors = hasErrors
            self.errorMessage = errorMessage
        }

        /// Empty result (for failed parsing)
        public static let empty = ExtractionResult(symbols: [], imports: [], hasErrors: true)
    }
}
