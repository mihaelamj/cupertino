@testable import CoreJSONParser
import CoreProtocols
import Foundation
import SharedConstants
import Testing

/// Regression suite for [#626](https://github.com/mihaelamj/cupertino/issues/626).
///
/// The v1.1.0 shipped bundle landed with `kind=unknown` for 162,821 of
/// 284,518 apple-docs rows (57%). Audit on the live DB found two causes:
///
/// 1. Apple's `metadata.roleHeading` was missing on a large slice of the
///    JSON corpus — particularly for pages auto-generated from
///    `@MainActor`-decorated structs, sample-code sub-pages, and
///    Obj-C-bridged headers. With no role heading, `parseKind` defaulted
///    to `.unknown` even though the page's `declaration.code` carried
///    authoritative Swift syntax (`struct Foo`, `enum Bar`, etc.).
///
/// 2. The `parseKind` dispatch tables didn't recognise the `case`,
///    `initializer`, `subscript`, `actor`, and `sample code` role headings
///    Apple emits in DocC. Even when `roleHeading` WAS present for these,
///    we dropped to `.unknown`.
///
/// Fix expands both `parseKind` tables (`AppleJSONToMarkdown` for the
/// structured-JSON path, `MarkdownToStructuredPage` for the markdown
/// fallback) and adds a declaration-token fallback `parseKindFromDeclaration`
/// in both. The fallback recovers ~109k of the 162k unknown rows on the
/// v1.1.0 corpus (~38% of all apple-docs rows) when the bundle is next
/// rebuilt.
@Suite("#626 Kind extraction expansion + declaration-token fallback", .serialized)
struct Issue626KindExtractionExpansionTests {
    typealias Kind = Shared.Models.StructuredDocumentationPage.Kind

    // MARK: - New Kind enum values

    @Test("Kind enum carries the 5 new cases with the expected raw values")
    func newKindCasesHaveExpectedRawValues() {
        #expect(Kind.enumCase.rawValue == "case")
        #expect(Kind.initializer.rawValue == "initializer")
        #expect(Kind.subscript.rawValue == "subscript")
        #expect(Kind.actor.rawValue == "actor")
        #expect(Kind.sampleCode.rawValue == "sample code")
    }

    @Test("Kind is round-trip Codable for the new cases")
    func newKindCasesAreCodable() throws {
        let kinds: [Kind] = [.enumCase, .initializer, .subscript, .actor, .sampleCode]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(Kind.self, from: data)
            #expect(decoded == kind, "round-trip failed for \(kind)")
        }
    }

    // MARK: - parseKindFromDeclaration (AppleJSONToMarkdown sibling — internal access)

    @Test(
        "Declaration-token fallback recognises the 14 common Swift declaration shapes (markdown path)",
        arguments: [
            ("struct Foo", Kind.struct),
            ("class Foo", Kind.class),
            ("enum Foo", Kind.enum),
            ("protocol Foo", Kind.protocol),
            ("actor Foo", Kind.actor),
            ("typealias Foo = Bar", Kind.typeAlias),
            ("case foo", Kind.enumCase),
            ("init(foo:)", Kind.initializer),
            ("init() async throws", Kind.initializer),
            ("convenience init(foo:)", Kind.initializer),
            ("subscript(index: Int) -> Foo", Kind.subscript),
            ("var foo: Bar { get }", Kind.property),
            ("let foo: Bar", Kind.property),
            ("func foo() -> Bar", Kind.method),
        ]
    )
    func declarationFallbackMarkdownPath(decl: String, expected: Kind) {
        let result = Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(decl)
        #expect(result == expected, "\(decl) should resolve to \(expected), got \(result?.rawValue ?? "nil")")
    }

    @Test("`class func` is matched as .method, not .class (longest-prefix wins)")
    func classFuncMatchesAsMethodNotClass() {
        let result = Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
            "class func endImpression(_ impression: SKAdImpression) async throws"
        )
        #expect(result == .method, "`class func` must match .method before the bare .class branch")
    }

    @Test("`class var` is matched as .property, not .class")
    func classVarMatchesAsProperty() {
        let result = Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
            "class var supportsSecureCoding: Bool { get }"
        )
        #expect(result == .property)
    }

    @Test("`static func` / `static var` / `mutating func` resolve to method/property")
    func staticAndMutatingResolveCorrectly() {
        #expect(
            Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
                "static func register(_ name: String) -> Foo"
            ) == .method
        )
        #expect(
            Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
                "static var shared: Foo { get }"
            ) == .property
        )
        #expect(
            Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
                "mutating func append(_ element: Element)"
            ) == .method
        )
    }

    @Test("@MainActor prefix is stripped before token matching")
    func mainActorAttributeStripped() {
        let result = Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
            "@MainActor\nstruct RequestReviewAction"
        )
        #expect(result == .struct, "`@MainActor` line must not block struct detection")
    }

    @Test("@available(...) prefix with parenthesised args is stripped")
    func availableAttributeStripped() {
        let result = Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
            "@available(iOS 16, macOS 13, *)\nclass Foo"
        )
        #expect(result == .class)
    }

    @Test("Empty / nil / whitespace-only declaration returns nil")
    func emptyDeclarationReturnsNil() {
        #expect(Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(nil) == nil)
        #expect(Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration("") == nil)
        #expect(Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration("   \n  \n") == nil)
    }

    @Test("Article-style declarations (no recognised first token) return nil")
    func unrecognisedDeclarationReturnsNil() {
        // An overview-only page with a non-Swift code block — the fallback
        // must NOT guess. Returning nil lets the caller keep `.unknown`
        // rather than fabricate a wrong kind.
        #expect(
            Core.JSONParser.MarkdownToStructuredPage.parseKindFromDeclaration(
                "// This is just a code comment"
            ) == nil
        )
    }

    // MARK: - #626 follow-up — parseKindFromSymbolKind (Apple's internal taxonomy)

    //
    // The roleHeading + declaration-token cascade landed in #633 cut the
    // unknown rate to ~19% on a projected reindex. The remaining residual
    // is mostly pages where Apple emits `metadata.symbolKind` but neither
    // a usable `roleHeading` nor a structured `declaration` block (common
    // for `enum.case` sub-pages, `associatedtype` requirements, and
    // `@MainActor`-decorated types that DocC renders without a heading).
    // `parseKindFromSymbolKind` mines `swift.struct` / `swift.func` /
    // `swift.enum.case` / etc. and sits between roleHeading and the
    // declaration-token fallback in the three-tier cascade.

    @Test(
        "parseKindFromSymbolKind handles every common Apple swift.* symbolKind",
        arguments: [
            ("swift.struct", Kind.struct),
            ("swift.class", Kind.class),
            ("swift.enum", Kind.enum),
            ("swift.enum.case", Kind.enumCase),
            ("swift.protocol", Kind.protocol),
            ("swift.actor", Kind.actor),
            ("swift.typealias", Kind.typeAlias),
            ("swift.macro", Kind.macro),
            ("swift.func", Kind.function),
            ("swift.method", Kind.method),
            ("swift.property", Kind.property),
            ("swift.init", Kind.initializer),
            ("swift.subscript", Kind.subscript),
            ("swift.operator", Kind.operator),
        ]
    )
    func symbolKindRecognisesSwiftTaxonomy(symbolKind: String, expected: Kind) {
        let result = Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind(symbolKind)
        #expect(result == expected, "\(symbolKind) → \(expected), got \(result?.rawValue ?? "nil")")
    }

    @Test(
        "parseKindFromSymbolKind handles Objective-C variants identically",
        arguments: [
            ("objc.class", Kind.class),
            ("objc.method", Kind.method),
            ("objc.property", Kind.property),
        ]
    )
    func symbolKindRecognisesObjcTaxonomy(symbolKind: String, expected: Kind) {
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind(symbolKind) == expected)
    }

    @Test("parseKindFromSymbolKind maps swift.associatedtype to .typeAlias")
    func associatedTypeMapsToTypeAlias() {
        // Associated types are shape-wise type declarations; no dedicated
        // Kind case so we route them to .typeAlias (closest existing
        // member) rather than dropping to .unknown.
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind("swift.associatedtype") == .typeAlias)
    }

    @Test("parseKindFromSymbolKind returns nil for swift.extension (no Kind case)")
    func extensionReturnsNil() {
        // Extensions adopt the kind of the type they extend; the helper
        // returns nil so the declaration-token tier can peek at the
        // first token (or `.unknown` survives if there's no declaration).
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind("swift.extension") == nil)
    }

    @Test("parseKindFromSymbolKind returns nil for nil input")
    func nilSymbolKindReturnsNil() {
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind(nil) == nil)
    }

    @Test("parseKindFromSymbolKind returns nil for unrecognised values (no false positives)")
    func unrecognisedSymbolKindReturnsNil() {
        // A future Apple addition or a malformed entry must NOT be
        // guessed at. Returning nil lets the declaration-token fallback
        // try, or `.unknown` survives — both better than a wrong tag.
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind("swift.somefutureshape") == nil)
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind("randomgarbage") == nil)
    }

    @Test("parseKindFromSymbolKind is case-insensitive")
    func caseInsensitive() {
        // Apple's emitted casing is consistently lowercase but we
        // normalise defensively in case the JSON ever shifts.
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind("Swift.Struct") == .struct)
        #expect(Core.JSONParser.AppleJSONToMarkdown.parseKindFromSymbolKind("SWIFT.FUNC") == .function)
    }
}
