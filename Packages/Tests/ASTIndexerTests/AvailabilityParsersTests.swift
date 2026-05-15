@testable import ASTIndexer
import Testing

/// Tests for ``ASTIndexer/AvailabilityParsers/extractAvailability(from:)``
/// focusing on the #221 multi-line fix. Single-line parity is already covered
/// by `CupertinoCoreTests.PackageAvailabilityAnnotatorTests`; the cases here
/// are the ones the old per-line regex scan silently dropped.
@Suite("AvailabilityParsers (#221 multi-line @available)")
struct AvailabilityParsersTests {
    @Test("Multi-line @available with each platform on its own line is captured")
    func multiLineEachPlatformOnOwnLine() {
        let source = """
        @available(
            iOS 16.0,
            macOS 13.0,
            *
        )
        func bar() {}
        """
        let attrs = ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        #expect(attrs.count == 1)
        let attr = attrs.first
        // Line is the line of the leading `@`, 1-indexed.
        #expect(attr?.line == 1)
        // Internal newlines + indentation collapsed to single spaces.
        #expect(attr?.raw == "(iOS 16.0, macOS 13.0, *)")
        #expect(attr?.platforms.contains("iOS") == true)
        #expect(attr?.platforms.contains("macOS") == true)
        #expect(attr?.platforms.contains("*") == true)
    }

    @Test("Multi-line @available with awkward indentation collapses to one-line raw")
    func multiLineAwkwardIndent() {
        let source = """
        struct Foo {
            @available(iOS 17.0,
                       macOS 14.0,
                       tvOS 17.0,
                       *)
            public func bar() {}
        }
        """
        let attrs = ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        #expect(attrs.count == 1)
        let attr = attrs.first
        #expect(attr?.line == 2)
        #expect(attr?.raw == "(iOS 17.0, macOS 14.0, tvOS 17.0, *)")
        #expect(attr?.platforms == ["iOS", "macOS", "tvOS", "*"])
    }

    @Test("Multi-line @available deprecated keyword form is captured")
    func multiLineDeprecatedKeyword() {
        let source = """
        @available(
            *,
            deprecated,
            message: "Use newFoo() instead"
        )
        func oldFoo() {}
        """
        let attrs = ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        #expect(attrs.count == 1)
        let attr = attrs.first
        #expect(attr?.line == 1)
        #expect(attr?.platforms.contains("*") == true)
        #expect(attr?.platforms.contains("deprecated") == true)
    }

    @Test("Two multi-line attrs stacked on same decl are both captured with correct lines")
    func twoMultiLineStacked() {
        let source = """
        @available(
            iOS 16.0,
            macOS 13.0,
            *
        )
        @available(
            *,
            deprecated,
            renamed: "newBar"
        )
        func bar() {}
        """
        let attrs = ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        #expect(attrs.count == 2)
        // First attr starts at line 1.
        #expect(attrs.first?.line == 1)
        // Second attr starts on the line after the first's closing paren.
        // Layout: 1=@available(, 2=iOS, 3=macOS, 4=*, 5=), 6=@available(
        #expect(attrs.last?.line == 6)
        #expect(attrs.last?.platforms.contains("deprecated") == true)
    }

    @Test("`@available` mentioned inside a string literal does NOT false-match")
    func availableInsideStringDoesNotMatch() {
        // Previously the per-line regex saw the substring "@available(" inside
        // the literal and produced a phantom Attribute. The AST walk doesn't
        // see tokens inside string content.
        let source = """
        let usage = "Add @available(iOS 16.0, *) to the declaration"
        func bar() {}
        """
        let attrs = ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        #expect(attrs.isEmpty)
    }

    @Test("`@available` inside a single-line comment does NOT match")
    func availableInsideCommentDoesNotMatch() {
        let source = """
        // @available(iOS 16.0, *) example in a doc comment
        func bar() {}
        """
        let attrs = ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        #expect(attrs.isEmpty)
    }

    @Test("Mixed single-line and multi-line attrs in the same source file")
    func mixedSingleAndMultiLine() {
        let source = """
        @available(iOS 16.0, *)
        func a() {}

        @available(
            iOS 17.0,
            macOS 14.0,
            *
        )
        func b() {}

        @available(*, deprecated)
        func c() {}
        """
        let attrs = ASTIndexer.AvailabilityParsers.extractAvailability(from: source)
        #expect(attrs.count == 3)
        #expect(attrs[0].raw == "(iOS 16.0, *)")
        #expect(attrs[0].line == 1)
        #expect(attrs[1].raw == "(iOS 17.0, macOS 14.0, *)")
        #expect(attrs[1].line == 4)
        #expect(attrs[2].raw == "(*, deprecated)")
        // Mixed-file layout: lines 1..2 = a, blank=3, 4..9 = b multi-line, blank=10, 11..12 = c.
        #expect(attrs[2].line == 11)
    }

    @Test("Empty source returns empty array")
    func emptySource() {
        #expect(ASTIndexer.AvailabilityParsers.extractAvailability(from: "").isEmpty)
    }

    @Test("Source with no @available returns empty array")
    func noAvailable() {
        let source = """
        struct Foo {
            func bar() {}
        }
        """
        #expect(ASTIndexer.AvailabilityParsers.extractAvailability(from: source).isEmpty)
    }
}
