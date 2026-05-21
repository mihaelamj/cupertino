import Foundation

extension Search {
    /// Direction the inheritance walker travels (#274).
    public enum InheritanceDirection: String, Sendable, CaseIterable, Codable {
        /// Follow `parentsOf` recursively — `UIButton ← UIControl ← UIView`.
        case up
        /// Follow `childrenOf` recursively — `UIControl → {UIButton, UISwitch, …}`.
        case down
        /// Walk both at once.
        case both
    }

    /// One candidate URI returned from `resolveSymbolURIs` (#274).
    ///
    /// Multiple candidates ambiguous symbol; caller surfaces a
    /// disambiguation list with the framework column. `Color` in
    /// SwiftUI vs AppKit is the canonical example.
    ///
    /// `kind` (#754 secondary) carries the symbol's `docs_metadata.kind`
    /// value (`class`, `protocol`, `struct`, `enum`, `actor`, etc.) so the
    /// empty-tree response can pick the right honest message: a class with
    /// no ancestors going `up` is a root type (e.g. NSObject), not a value
    /// type or protocol. `nil` when the resolver couldn't read the column
    /// (pre-v18 schemas or callers that didn't fetch it).
    public struct InheritanceCandidate: Sendable, Hashable, Codable {
        public let uri: String
        public let framework: String
        public let title: String
        public let kind: String?

        public init(uri: String, framework: String, title: String, kind: String? = nil) {
            self.uri = uri
            self.framework = framework
            self.title = title
            self.kind = kind
        }
    }

    /// Choose the right empty-tree message for `get_inheritance` /
    /// `cupertino inheritance` based on the symbol's `kind` and the walk
    /// direction (#754).
    ///
    /// Pre-fix the response always said "Swift value types and protocols
    /// don't carry inherits-from edges", which is wrong for an Objective-C
    /// class at the root of its hierarchy (NSObject going `up`). This
    /// helper differentiates the cases:
    ///
    /// - `class` going `up`: root type, no ancestors above.
    /// - `class` going `down`: no descendants indexed below.
    /// - `class` going `both`: isolated class with neither ancestors nor
    ///   descendants in the indexed corpus.
    /// - `protocol`: directs the caller at `search_conformances` (the
    ///   right surface for protocol conformance edges).
    /// - `struct` / `enum` / `actor`: value-type-ish; no inheritance graph.
    /// - any other kind (or `nil` when the resolver didn't fetch it):
    ///   fall back to the legacy generic prose so older callers keep the
    ///   same output shape.
    ///
    /// Every return value starts with the `_No inheritance data` marker
    /// (per the #669 semantic-marker contract) so AI clients that grep for
    /// it keep working; the explanatory prose after the marker is what
    /// changes per case.
    public static func emptyInheritanceMessage(
        kind: String?,
        direction: InheritanceDirection
    ) -> String {
        let lowered = kind?.lowercased()
        let reason: String
        switch lowered {
        case "class":
            switch direction {
            case .up:
                reason = "Root type: no ancestors above this class in the indexed corpus."
            case .down:
                reason = "No descendants indexed under this class."
            case .both:
                reason = "Isolated class: neither ancestors nor descendants indexed in the corpus."
            }
        case "protocol":
            reason = "Swift protocol: protocols don't carry inherits-from edges. " +
                "Try `search_conformances` for the types that conform to this protocol."
        case "struct", "enum", "actor":
            reason = "Swift value type (`\(lowered ?? "")`): value types don't carry inherits-from edges."
        default:
            reason = "Swift value types and protocols don't carry inherits-from edges. " +
                "Check `search_conformances` if you're looking for protocol conformance instead."
        }
        return "_No inheritance data: \(reason)_"
    }

    /// One node in a walked inheritance tree (#274).
    ///
    /// `children` are the next level of neighbours in the walker's
    /// direction (parents-of-this for an upward walk, children-of-this
    /// for a downward walk).
    public struct InheritanceNode: Sendable, Hashable, Codable {
        public let uri: String
        public let children: [InheritanceNode]

        public init(uri: String, children: [InheritanceNode] = []) {
            self.uri = uri
            self.children = children
        }
    }

    /// Result of `walkInheritance` (#274) — the starting URI plus the
    /// two neighbour trees. Either tree is empty when the direction
    /// wasn't requested (`.up` leaves `descendants` empty,
    /// `.down` leaves `ancestors` empty).
    public struct InheritanceTree: Sendable, Hashable, Codable {
        public let startURI: String
        public let ancestors: [InheritanceNode]
        public let descendants: [InheritanceNode]

        public init(
            startURI: String,
            ancestors: [InheritanceNode],
            descendants: [InheritanceNode]
        ) {
            self.startURI = startURI
            self.ancestors = ancestors
            self.descendants = descendants
        }

        /// True when the tree has no neighbours in either direction.
        /// Useful for the "no inheritance data" empty-result case.
        public var isEmpty: Bool {
            ancestors.isEmpty && descendants.isEmpty
        }
    }
}
