import ASTIndexer
import Foundation
import Testing

// MARK: - #759 iter 1. AST extractor's GenericWhereClause walk

//
// Pinned per #763 acceptance Section 1. The pre-#759 extractor only
// walked `GenericParameterClauseSyntax.parameters` (inline `<T: View>`
// form); the where-clause syntax node was being dropped on the floor.
// #759 added a second walk over `GenericWhereClauseSyntax.requirements`
// filtered to `.conformanceRequirement` (drops same-type T == U).
//
// Per the acceptance list, each declaration kind that has a
// where-clause attachment point needs its own coverage:
//   - function, struct, class, enum, actor, protocol, extension, typealias
//
// Plus per-pattern coverage:
//   - inline only (`<T: View>`)
//   - where only (`where T: View`)
//   - both
//   - composed constraints (`T: Hashable & Sendable`)
//   - same-type filtered (`T == U` dropped)
//   - neither (bare names only)
//   - empty generic clause

@Suite("#759 iter-1. AST GenericWhereClause walk per-decl-kind matrix")
struct Issue759WhereClauseExtractionTests {
    private let extractor = ASTIndexer.Extractor()

    /// Find the first symbol with the given name in the extraction
    /// result, returning its generic-parameters array.
    private func genericParams(for name: String, in source: String) -> [String] {
        let result = extractor.extract(from: source)
        return result.symbols.first(where: { $0.name == name })?.genericParameters ?? []
    }

    // MARK: - Pattern coverage on function decl

    @Test("function: inline `<T: View>` only emits `T: View`")
    func functionInlineOnly() {
        let source = "func foo<T: View>(_ x: T) {}"
        #expect(genericParams(for: "foo", in: source) == ["T: View"])
    }

    @Test("function: `where T: View` only emits `T: View`")
    func functionWhereClauseOnly() {
        let source = "func foo<T>(_ x: T) where T: View {}"
        let result = genericParams(for: "foo", in: source)
        // Bare `T` from the inline clause + `T: View` from where-clause walk
        #expect(result == ["T", "T: View"], "inline bare + where-clause → both entries; got \(result)")
    }

    @Test("function: BOTH inline `<T: View>` AND `where U: Hashable` emit both entries")
    func functionInlineAndWhere() {
        let source = "func foo<T: View, U>(_ x: T, _ y: U) where U: Hashable {}"
        let result = genericParams(for: "foo", in: source)
        #expect(result == ["T: View", "U", "U: Hashable"], "inline + where merged in order; got \(result)")
    }

    @Test("function: same-type requirement `T == U` is filtered out of output")
    func functionSameTypeFiltered() {
        let source = "func foo<T, U>(_ x: T, _ y: U) where T == U {}"
        let result = genericParams(for: "foo", in: source)
        // Inline bare names retained; same-type where-clause dropped
        // because `.conformanceRequirement` filter excludes it.
        #expect(result == ["T", "U"], "same-type requirement filtered; got \(result)")
    }

    @Test("function: composed constraint `T: Hashable & Sendable` emits intact")
    func functionComposedConstraint() {
        let source = "func foo<T>(_ x: T) where T: Hashable & Sendable {}"
        let result = genericParams(for: "foo", in: source)
        #expect(result == ["T", "T: Hashable & Sendable"], "composed constraint preserved; got \(result)")
    }

    @Test("function: no generics → empty array")
    func functionNoGenerics() {
        let source = "func foo() {}"
        #expect(genericParams(for: "foo", in: source).isEmpty)
    }

    @Test("function: bare generics no where-clause → bare names only")
    func functionBareGenericsNoWhere() {
        let source = "func foo<T, U>(_ x: T, _ y: U) {}"
        #expect(genericParams(for: "foo", in: source) == ["T", "U"])
    }

    // MARK: - Per-decl-kind matrix

    @Test("struct: where-clause walked end-to-end")
    func structWhereClause() {
        let source = "struct Foo<Data> where Data: RandomAccessCollection {}"
        let result = genericParams(for: "Foo", in: source)
        #expect(result == ["Data", "Data: RandomAccessCollection"], "struct where-clause captured; got \(result)")
    }

    @Test("class: where-clause walked end-to-end")
    func classWhereClause() {
        let source = "class Bar<T> where T: NSObject {}"
        let result = genericParams(for: "Bar", in: source)
        #expect(result == ["T", "T: NSObject"], "class where-clause captured; got \(result)")
    }

    @Test("enum: where-clause walked end-to-end")
    func enumWhereClause() {
        let source = "enum Baz<T> where T: Equatable { case one(T) }"
        let result = genericParams(for: "Baz", in: source)
        #expect(result == ["T", "T: Equatable"], "enum where-clause captured; got \(result)")
    }

    @Test("actor: where-clause walked end-to-end")
    func actorWhereClause() {
        let source = "actor Qux<T> where T: Sendable {}"
        let result = genericParams(for: "Qux", in: source)
        #expect(result == ["T", "T: Sendable"], "actor where-clause captured; got \(result)")
    }

    @Test("protocol: where-clause walked end-to-end (primary associated-type style)")
    func protocolWhereClause() {
        // Note: protocols don't have an inline generic-parameter clause
        // in the same way as struct/class. The extractor's protocol visit
        // passes `genericParameterClause: nil` and only walks the
        // where-clause for the protocol's primary-associated-type
        // constraint shape.
        let source = "protocol Bag<Element> where Element: Hashable {}"
        let result = genericParams(for: "Bag", in: source)
        #expect(result == ["Element: Hashable"], "protocol where-clause captured; got \(result)")
    }

    @Test("extension: where-clause is the primary constraint surface")
    func extensionWhereClause() {
        // Extensions don't have their own generic-parameter clause;
        // they inherit from the extended type. Constraints live entirely
        // in the where-clause. Pre-#759 this was completely dropped.
        let source = "extension Collection where Element: Equatable {}"
        let result = genericParams(for: "Collection", in: source)
        #expect(result == ["Element: Equatable"], "extension where-clause captured; got \(result)")
    }

    @Test("typealias: where-clause walked end-to-end")
    func typealiasWhereClause() {
        let source = "typealias MyAlias<T> = Array<T> where T: Hashable"
        let result = genericParams(for: "MyAlias", in: source)
        #expect(result == ["T", "T: Hashable"], "typealias where-clause captured; got \(result)")
    }

    // MARK: - Empty generic clause edge case

    @Test("Symbol with no generic clause at all: empty genericParameters array")
    func noGenericClauseEmptyArray() {
        let source = "struct Color {}"
        #expect(genericParams(for: "Color", in: source).isEmpty)
    }

    // MARK: - Multi-param where clause

    @Test("function: multi-constraint where clause emits each as a separate entry")
    func functionMultiParamWhere() {
        let source = "func foo<T, U>(_ x: T, _ y: U) where T: View, U: Hashable {}"
        let result = genericParams(for: "foo", in: source)
        #expect(result == ["T", "U", "T: View", "U: Hashable"], "multi-where → each conformance is a separate entry; got \(result)")
    }
}
