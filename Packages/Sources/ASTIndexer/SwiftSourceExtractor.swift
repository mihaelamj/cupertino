// SwiftSourceExtractor.swift
// Main API for extracting symbols from Swift source code (#81)

import Foundation
import SwiftParser
import SwiftSyntax

extension ASTIndexer {
    /// Extracts symbols and imports from Swift source code using SwiftSyntax
    public struct SwiftSourceExtractor: Sendable {
        public init() {}

        /// Extract symbols and imports from Swift source code
        /// - Parameter source: Swift source code string
        /// - Returns: Extraction result containing symbols, imports, and error status
        public func extract(from source: String) -> ExtractionResult {
            // Parse source into syntax tree
            let tree = Parser.parse(source: source)

            // Create visitor and walk the tree
            let visitor = DeclarationVisitor(source: source)
            visitor.walk(tree)

            return ExtractionResult(
                symbols: visitor.symbols,
                imports: visitor.imports,
                hasErrors: tree.hasError
            )
        }

        /// Extract symbols from a file URL
        /// - Parameter url: File URL to parse
        /// - Returns: Extraction result, or empty result with error if file cannot be read
        public func extract(from url: URL) -> ExtractionResult {
            do {
                let source = try String(contentsOf: url, encoding: .utf8)
                return extract(from: source)
            } catch {
                return ExtractionResult(
                    symbols: [],
                    imports: [],
                    hasErrors: true,
                    errorMessage: "Failed to read file: \(error.localizedDescription)"
                )
            }
        }
    }
}

// MARK: - Declaration Visitor

/// SyntaxVisitor that extracts declarations from Swift source
private final class DeclarationVisitor: SyntaxVisitor {
    private let source: String
    private let sourceLocationConverter: SourceLocationConverter

    private(set) var symbols: [ASTIndexer.ExtractedSymbol] = []
    private(set) var imports: [ASTIndexer.ExtractedImport] = []

    init(source: String) {
        self.source = source
        let tree = Parser.parse(source: source)
        sourceLocationConverter = SourceLocationConverter(fileName: "", tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Imports

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.map(\.name.text).joined(separator: ".")
        let location = node.startLocation(converter: sourceLocationConverter)
        let isExported = node.attributes.contains { attr in
            attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported"
        }

        imports.append(ASTIndexer.ExtractedImport(
            moduleName: moduleName,
            line: location.line,
            isExported: isExported
        ))

        return .visitChildren
    }

    // MARK: - Type Declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = extractTypeDeclaration(
            name: node.name.text,
            kind: .class,
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            genericParameterClause: node.genericParameterClause,
            startPosition: node.positionAfterSkippingLeadingTrivia
        )
        symbols.append(symbol)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = extractTypeDeclaration(
            name: node.name.text,
            kind: .struct,
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            genericParameterClause: node.genericParameterClause,
            startPosition: node.positionAfterSkippingLeadingTrivia
        )
        symbols.append(symbol)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = extractTypeDeclaration(
            name: node.name.text,
            kind: .enum,
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            genericParameterClause: node.genericParameterClause,
            startPosition: node.positionAfterSkippingLeadingTrivia
        )
        symbols.append(symbol)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = extractTypeDeclaration(
            name: node.name.text,
            kind: .actor,
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            genericParameterClause: node.genericParameterClause,
            startPosition: node.positionAfterSkippingLeadingTrivia
        )
        symbols.append(symbol)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = extractTypeDeclaration(
            name: node.name.text,
            kind: .protocol,
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            genericParameterClause: nil,
            startPosition: node.positionAfterSkippingLeadingTrivia
        )
        symbols.append(symbol)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let conformances = extractConformances(from: node.inheritanceClause)
        let attributes = extractAttributes(from: node.attributes)

        symbols.append(ASTIndexer.ExtractedSymbol(
            name: name,
            kind: .extension,
            line: location.line,
            column: location.column,
            attributes: attributes,
            conformances: conformances
        ))

        return .visitChildren
    }

    // MARK: - Functions and Methods

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)
        let isPublic = hasPublicModifier(node.modifiers)
        let isStatic = hasStaticModifier(node.modifiers)
        let isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = node.signature.effectSpecifiers?.throwsClause != nil

        // Build signature
        let signature = buildFunctionSignature(node)

        // Determine if it's a method (inside a type) or free function
        let kind: ASTIndexer.SymbolKind = isInsideTypeDeclaration(node) ? .method : .function

        let genericParams = extractGenericParameters(from: node.genericParameterClause)

        symbols.append(ASTIndexer.ExtractedSymbol(
            name: node.name.text,
            kind: kind,
            line: location.line,
            column: location.column,
            signature: signature,
            isAsync: isAsync,
            isThrows: isThrows,
            isPublic: isPublic,
            isStatic: isStatic,
            attributes: attributes,
            genericParameters: genericParams
        ))

        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)
        let isPublic = hasPublicModifier(node.modifiers)
        let isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = node.signature.effectSpecifiers?.throwsClause != nil

        let signature = "init\(node.signature.trimmedDescription)"

        symbols.append(ASTIndexer.ExtractedSymbol(
            name: "init",
            kind: .initializer,
            line: location.line,
            column: location.column,
            signature: signature,
            isAsync: isAsync,
            isThrows: isThrows,
            isPublic: isPublic,
            attributes: attributes
        ))

        return .visitChildren
    }

    // MARK: - Properties

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)
        let isPublic = hasPublicModifier(node.modifiers)
        let isStatic = hasStaticModifier(node.modifiers)

        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                symbols.append(ASTIndexer.ExtractedSymbol(
                    name: pattern.identifier.text,
                    kind: .property,
                    line: location.line,
                    column: location.column,
                    isPublic: isPublic,
                    isStatic: isStatic,
                    attributes: attributes
                ))
            }
        }

        return .visitChildren
    }

    // MARK: - Enum Cases

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)

        for element in node.elements {
            symbols.append(ASTIndexer.ExtractedSymbol(
                name: element.name.text,
                kind: .case,
                line: location.line,
                column: location.column,
                attributes: attributes
            ))
        }

        return .visitChildren
    }

    // MARK: - Type Aliases

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)
        let isPublic = hasPublicModifier(node.modifiers)
        let genericParams = extractGenericParameters(from: node.genericParameterClause)

        symbols.append(ASTIndexer.ExtractedSymbol(
            name: node.name.text,
            kind: .typealias,
            line: location.line,
            column: location.column,
            isPublic: isPublic,
            attributes: attributes,
            genericParameters: genericParams
        ))

        return .visitChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)

        symbols.append(ASTIndexer.ExtractedSymbol(
            name: node.name.text,
            kind: .associatedtype,
            line: location.line,
            column: location.column,
            attributes: attributes
        ))

        return .visitChildren
    }

    // MARK: - Subscripts

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)
        let isPublic = hasPublicModifier(node.modifiers)
        let isStatic = hasStaticModifier(node.modifiers)

        let signature = "subscript\(node.parameterClause.trimmedDescription) -> \(node.returnClause.type.trimmedDescription)"

        symbols.append(ASTIndexer.ExtractedSymbol(
            name: "subscript",
            kind: .subscript,
            line: location.line,
            column: location.column,
            signature: signature,
            isPublic: isPublic,
            isStatic: isStatic,
            attributes: attributes
        ))

        return .visitChildren
    }

    // MARK: - Macros

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let attributes = extractAttributes(from: node.attributes)
        let isPublic = hasPublicModifier(node.modifiers)

        symbols.append(ASTIndexer.ExtractedSymbol(
            name: node.name.text,
            kind: .macro,
            line: location.line,
            column: location.column,
            isPublic: isPublic,
            attributes: attributes
        ))

        return .visitChildren
    }

    // MARK: - Helpers

    private func extractTypeDeclaration(
        name: String,
        kind: ASTIndexer.SymbolKind,
        attributes: AttributeListSyntax,
        modifiers: DeclModifierListSyntax,
        inheritanceClause: InheritanceClauseSyntax?,
        genericParameterClause: GenericParameterClauseSyntax?,
        startPosition: AbsolutePosition
    ) -> ASTIndexer.ExtractedSymbol {
        let location = sourceLocationConverter.location(for: startPosition)
        let extractedAttributes = extractAttributes(from: attributes)
        let conformances = extractConformances(from: inheritanceClause)
        let isPublic = hasPublicModifier(modifiers)
        let genericParams = extractGenericParameters(from: genericParameterClause)

        return ASTIndexer.ExtractedSymbol(
            name: name,
            kind: kind,
            line: location.line,
            column: location.column,
            isPublic: isPublic,
            attributes: extractedAttributes,
            conformances: conformances,
            genericParameters: genericParams
        )
    }

    private func extractAttributes(from attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element -> String? in
            guard let attr = element.as(AttributeSyntax.self) else { return nil }
            let name = attr.attributeName.trimmedDescription
            if let args = attr.arguments {
                return "@\(name)(\(args.trimmedDescription))"
            }
            return "@\(name)"
        }
    }

    private func extractConformances(from inheritanceClause: InheritanceClauseSyntax?) -> [String] {
        guard let clause = inheritanceClause else { return [] }
        return clause.inheritedTypes.map(\.type.trimmedDescription)
    }

    private func extractGenericParameters(from clause: GenericParameterClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.parameters.map { param in
            if let constraint = param.inheritedType {
                return "\(param.name.text): \(constraint.trimmedDescription)"
            }
            return param.name.text
        }
    }

    private func hasPublicModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            let name = modifier.name.text
            return name == "public" || name == "open"
        }
    }

    private func hasStaticModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            let name = modifier.name.text
            return name == "static" || name == "class"
        }
    }

    private func buildFunctionSignature(_ node: FunctionDeclSyntax) -> String {
        var sig = "func \(node.name.text)"
        if let generics = node.genericParameterClause {
            sig += generics.trimmedDescription
        }
        sig += node.signature.trimmedDescription
        return sig
    }

    private func isInsideTypeDeclaration(_ node: some SyntaxProtocol) -> Bool {
        var current: Syntax? = Syntax(node)
        while let parent = current?.parent {
            if parent.is(ClassDeclSyntax.self) ||
                parent.is(StructDeclSyntax.self) ||
                parent.is(EnumDeclSyntax.self) ||
                parent.is(ActorDeclSyntax.self) ||
                parent.is(ProtocolDeclSyntax.self) ||
                parent.is(ExtensionDeclSyntax.self) {
                return true
            }
            current = parent
        }
        return false
    }
}
