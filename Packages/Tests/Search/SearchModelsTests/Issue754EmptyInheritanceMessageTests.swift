import Foundation
import SearchModels
import Testing

// MARK: - #754 secondary -- empty-tree message picks the right honest wording

//
// Surfaced during 2026-05-21 autopilot merit-audit (pass 22 functional probe).
// Pre-fix, `get_inheritance(symbol: "NSObject", direction: "up")` against the
// brew v1.2.0 binary returned:
//
//   "No inheritance data: Swift value types and protocols don't carry
//    inherits-from edges. Check `search_conformances` if you're looking for
//    protocol conformance instead."
//
// That message is wrong for an Objective-C class at the root of its
// inheritance hierarchy. NSObject is a class, not a Swift value type or a
// protocol. Going `up` from the root, the honest response is "no ancestors
// above", not blaming value types and protocols.
//
// Fix: extend `Search.InheritanceCandidate` with `kind` (from
// `docs_metadata.kind`), and route the empty-tree formatter through
// `Search.emptyInheritanceMessage(kind:direction:)` which picks the right
// prose per (kind, direction) pair.
//
// This suite is the regression lock. The 10 canonical-root parametrised
// sub-suite mirrors the shape of `Issue754NSObjectResolverSuffixTests`
// (the resolver-side regression lock from the primary fix in v1.2.0).
//

@Suite("#754 secondary: empty-tree message picks honest wording")
struct Issue754EmptyInheritanceMessageTests {
    // MARK: - Semantic-marker contract: every empty-message starts with "_No inheritance data"

    @Test(
        "every empty-message variant carries the '_No inheritance data' semantic marker (#669 contract)",
        arguments: [
            ("class", Search.InheritanceDirection.up),
            ("class", .down),
            ("class", .both),
            ("protocol", .up),
            ("struct", .up),
            ("enum", .up),
            ("actor", .up),
            ("typealias", .up), // unknown kind: fallback
            ("", .up), // empty kind: fallback
        ]
    )
    func everyVariantCarriesSemanticMarker(_ pair: (String, Search.InheritanceDirection)) {
        let message = Search.emptyInheritanceMessage(kind: pair.0, direction: pair.1)
        #expect(
            message.hasPrefix("_No inheritance data:"),
            "kind=\(pair.0) direction=\(pair.1) should start with the '_No inheritance data:' marker; got: \(message)"
        )
        #expect(message.hasSuffix("_"))
    }

    @Test("nil-kind variant also carries the semantic marker")
    func nilKindCarriesSemanticMarker() {
        let message = Search.emptyInheritanceMessage(kind: nil, direction: .up)
        #expect(message.hasPrefix("_No inheritance data:"))
    }

    // MARK: - Class going up: root type, no ancestors

    @Test("class going up: reason names 'Root type', not 'value types and protocols'")
    func classGoingUpIsRootType() {
        let message = Search.emptyInheritanceMessage(kind: "class", direction: .up)
        #expect(message.contains("Root type"))
        #expect(message.contains("no ancestors"))
        #expect(!message.contains("Swift value types and protocols don't carry"))
    }

    @Test(
        "10 canonical root types: 'class' kind + direction `up` reason names 'Root type'",
        arguments: [
            "NSObject", "NSResponder", "UIView", "UIResponder", "UIViewController",
            "NSView", "NSViewController", "CALayer", "NSManagedObject", "UIControl",
        ]
    )
    func canonicalRootTypesGetRootMessage(_ rootName: String) {
        // The 10 names are the same set the primary-fix regression lock
        // (Issue754NSObjectResolverSuffixTests) covers. We don't need to
        // seed a DB for the message-formatter test; we just verify that
        // when the resolver returns kind=class and the walker returns an
        // empty up-tree, the formatter produces the honest message.
        let message = Search.emptyInheritanceMessage(kind: "class", direction: .up)
        #expect(
            message.contains("Root type"),
            "kind=class + direction=up should name 'Root type' for \(rootName)"
        )
    }

    // MARK: - Class going down: no descendants

    @Test("class going down: reason names 'No descendants'")
    func classGoingDownIsLeafType() {
        let message = Search.emptyInheritanceMessage(kind: "class", direction: .down)
        #expect(message.contains("No descendants"))
        #expect(!message.contains("Swift value types and protocols don't carry"))
    }

    // MARK: - Class going both: isolated class

    @Test("class going both: reason names 'Isolated class'")
    func classGoingBothIsIsolated() {
        let message = Search.emptyInheritanceMessage(kind: "class", direction: .both)
        #expect(message.contains("Isolated class"))
        #expect(!message.contains("Swift value types and protocols don't carry"))
    }

    // MARK: - Protocol: directs at search_conformances

    @Test("protocol: directs at search_conformances regardless of direction")
    func protocolDirectsAtConformances() {
        for direction in Search.InheritanceDirection.allCases {
            let message = Search.emptyInheritanceMessage(kind: "protocol", direction: direction)
            #expect(
                message.contains("Swift protocol"),
                "protocol kind in direction=\(direction) should say 'Swift protocol'"
            )
            #expect(
                message.contains("search_conformances"),
                "protocol kind in direction=\(direction) should direct at search_conformances"
            )
        }
    }

    // MARK: - Value types: struct / enum / actor

    @Test(
        "value types: reason names 'Swift value type' with the specific kind",
        arguments: ["struct", "enum", "actor"]
    )
    func valueTypesGetValueTypeMessage(_ kind: String) {
        let message = Search.emptyInheritanceMessage(kind: kind, direction: .up)
        #expect(message.contains("Swift value type"))
        #expect(message.contains("`\(kind)`"))
        #expect(!message.contains("Swift protocol"))
        #expect(!message.contains("Root type"))
    }

    // MARK: - Case insensitivity: stored kind may be lowercased or mixed-case

    @Test(
        "kind matching is case-insensitive",
        arguments: ["Class", "CLASS", "class", "ClAsS"]
    )
    func kindIsLowercased(_ kind: String) {
        let message = Search.emptyInheritanceMessage(kind: kind, direction: .up)
        #expect(
            message.contains("Root type"),
            "kind=\(kind) should normalise to lowercase and produce class-up reason"
        )
    }

    // MARK: - Fallback: nil kind or unknown kind keeps legacy generic reason

    @Test("nil kind: falls back to legacy generic reason")
    func nilKindFallsBackToLegacy() {
        let message = Search.emptyInheritanceMessage(kind: nil, direction: .up)
        #expect(
            message.contains("value types and protocols"),
            "nil kind should keep legacy generic reason (back-compat for older callers)"
        )
        #expect(
            message.contains("search_conformances"),
            "nil kind should still mention search_conformances"
        )
    }

    @Test(
        "unknown kind: falls back to legacy generic reason",
        arguments: ["typealias", "extension", "function", "property", "case", ""]
    )
    func unknownKindFallsBack(_ kind: String) {
        let message = Search.emptyInheritanceMessage(kind: kind, direction: .up)
        #expect(
            message.contains("value types and protocols") || message.contains("Swift value type"),
            "kind=\(kind) (unknown to the helper) should fall back to legacy reason"
        )
    }

    // MARK: - InheritanceCandidate carries kind

    @Test("InheritanceCandidate.kind is part of the public init signature")
    func candidateCarriesKind() {
        let candidate = Search.InheritanceCandidate(
            uri: "apple-docs://objectivec/nsobject-swift.class",
            framework: "objectivec",
            title: "NSObject",
            kind: "class"
        )
        #expect(candidate.kind == "class")

        // Default-nil for back-compat with callers that don't fetch kind.
        let legacyShape = Search.InheritanceCandidate(
            uri: "apple-docs://foundation/url",
            framework: "foundation",
            title: "URL"
        )
        #expect(legacyShape.kind == nil)
    }
}
