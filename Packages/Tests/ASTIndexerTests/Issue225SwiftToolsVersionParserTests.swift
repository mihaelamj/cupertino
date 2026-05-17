import ASTIndexer
import Foundation
import Testing

// MARK: - #225 Part A — parseSwiftToolsVersion pure-function contract

//
// SwiftPM's contract: the first non-blank line of `Package.swift` must
// be the `// swift-tools-version: X.Y` declaration (SE-0152). The
// parser regex-matches that exact shape on the first non-blank line
// and returns nil for anything that doesn't conform.
//
// This file pins the parser's behaviour across the shapes we expect
// to see in the wild (well-formed, minor-only, patch-suffixed, with
// or without surrounding whitespace, leading blank lines) and the
// shapes we explicitly DON'T want to match (declaration buried under
// other comments, version on the wrong line, malformed values).

@Suite("#225 Part A — parseSwiftToolsVersion pure-function contract", .serialized)
struct Issue225SwiftToolsVersionParserTests {
    // MARK: - 1. Standard happy path

    @Test(
        "canonical declarations parse to major.minor",
        arguments: [
            ("// swift-tools-version: 5.7\nimport PackageDescription", "5.7"),
            ("// swift-tools-version: 6.0\nimport PackageDescription", "6.0"),
            ("// swift-tools-version: 5.10\nimport PackageDescription", "5.10"),
            ("//swift-tools-version:6.1\nimport PackageDescription", "6.1"),
            ("// swift-tools-version:6.2\nimport PackageDescription", "6.2"),
            ("//  swift-tools-version :  5.9  \nimport PackageDescription", "5.9"),
        ]
    )
    func canonicalDeclarations(input: String, expected: String) {
        #expect(
            ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input) == expected,
            "input: \(input.prefix(40))…"
        )
    }

    // MARK: - 2. Leading blank lines tolerated

    @Test("leading blank lines tolerated (SwiftPM doesn't require declaration on line 1 byte 0)")
    func leadingBlankLines() {
        let input = """


        // swift-tools-version: 6.0
        import PackageDescription
        """
        #expect(ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input) == "6.0")
    }

    @Test("leading whitespace-only lines tolerated")
    func leadingWhitespaceOnlyLines() {
        let input = "   \n\t\n// swift-tools-version: 5.8\nimport PackageDescription"
        #expect(ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input) == "5.8")
    }

    // MARK: - 3. Negative shapes — return nil

    @Test("declaration after a non-blank non-matching line returns nil (SwiftPM also rejects this)")
    func declarationBuriedBelowOtherCode() {
        let input = """
        // Copyright (c) 2025
        // swift-tools-version: 6.0
        import PackageDescription
        """
        // The first non-blank line is the copyright comment, not the
        // tools-version declaration. Return nil.
        #expect(ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input) == nil)
    }

    @Test("empty input returns nil")
    func emptyInput() {
        #expect(ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: "") == nil)
    }

    @Test("blank-only input returns nil")
    func blankOnlyInput() {
        #expect(ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: "\n\n\n   \n\t") == nil)
    }

    @Test(
        "malformed declarations return nil",
        arguments: [
            "swift-tools-version: 5.7", // missing //
            "// swift-tools-version 5.7", // missing :
            "// swift-tools-version: five.seven", // non-numeric
            "// swift-tools-version: 5", // major only — not the X.Y shape
            "// SWIFT-TOOLS-VERSION: 6.0", // case-sensitive (Swift's parser is)
        ]
    )
    func malformedDeclarations(input: String) {
        #expect(
            ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input) == nil,
            "expected nil for: \(input)"
        )
    }

    // MARK: - 4. Patch version is truncated

    @Test(
        "patch version stripped — column stores major.minor",
        arguments: [
            ("// swift-tools-version: 5.7.1", "5.7"),
            ("// swift-tools-version: 6.0.3", "6.0"),
            ("// swift-tools-version: 5.10.0", "5.10"),
        ]
    )
    func patchVersionTruncated(input: String, expected: String) {
        // Regex `(\d+\.\d+)` is non-greedy on patch — captures only
        // the first major.minor pair. Locks the contract.
        #expect(
            ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input) == expected,
            "input: \(input)"
        )
    }

    // MARK: - 5. Real-world Package.swift shape

    @Test("realistic Package.swift round-trips cleanly")
    func realisticManifest() {
        let manifest = """
        // swift-tools-version: 6.0
        // The swift-tools-version declares the minimum version of Swift required to build this package.

        import PackageDescription

        let package = Package(
            name: "MyLib",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [.library(name: "MyLib", targets: ["MyLib"])],
            targets: [.target(name: "MyLib")]
        )
        """
        #expect(ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: manifest) == "6.0")
    }

    // MARK: - 6. Idempotency

    @Test("parser is pure — same input yields same output (no shared state)")
    func parserIsPure() {
        let input = "// swift-tools-version: 5.9\nimport PackageDescription"
        let first = ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input)
        let second = ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input)
        let third = ASTIndexer.AvailabilityParsers.parseSwiftToolsVersion(from: input)
        #expect(first == second)
        #expect(second == third)
        #expect(first == "5.9")
    }
}
