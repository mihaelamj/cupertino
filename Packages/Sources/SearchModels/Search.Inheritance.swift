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
    /// Multiple candidates → ambiguous symbol; caller surfaces a
    /// disambiguation list with the framework column. `Color` in
    /// SwiftUI vs AppKit is the canonical example.
    public struct InheritanceCandidate: Sendable, Hashable, Codable {
        public let uri: String
        public let framework: String
        public let title: String

        public init(uri: String, framework: String, title: String) {
            self.uri = uri
            self.framework = framework
            self.title = title
        }
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
