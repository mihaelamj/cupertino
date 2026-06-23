import Foundation

// MARK: - Search.SourceHierarchy

extension Search {
    /// A source's self-described browse hierarchy: how many levels it has, the kind of node at
    /// each level, which level is the leaf, and what content type that leaf carries. The unified
    /// `list` tool is driven entirely by this descriptor, so navigation hardcodes nothing about a
    /// given source. `list(source)` (level 0) returns this; `list(source, level:N, parent:…)`
    /// walks it.
    ///
    /// One source is one DB, and sources disagree on shape: apple-docs is framework -> page ->
    /// topic-group (3 levels), while swift-evolution is a flat list of proposals (1 level). The
    /// descriptor captures that difference declaratively, replacing the source-blind
    /// `list_frameworks` (a leftover from the source-independence work) and the desktop's
    /// hardcoded per-source framework tables.
    public struct SourceHierarchy: Codable, Equatable, Sendable {
        /// One rung of the hierarchy, 1-based from the top.
        public struct Level: Codable, Equatable, Sendable {
            /// 1-based depth from the top (level 1 is the root listing, e.g. frameworks).
            public let level: Int
            /// Human/semantic kind of the nodes AT this level: "framework", "proposal",
            /// "page", "topic-group", "symbol", "file", … Display-facing; not an enum so a
            /// new source can name its levels without a contract change.
            public let kind: String
            /// True for the deepest level, whose nodes are readable documents (`read_document`).
            public let isLeaf: Bool

            public init(level: Int, kind: String, isLeaf: Bool) {
                self.level = level
                self.kind = kind
                self.isLeaf = isLeaf
            }
        }

        /// The rungs, ordered top (level 1) to leaf. Never empty.
        public let levels: [Level]
        /// The content type a leaf document carries, so a client knows how to render it.
        public let leafContentType: LeafContentType

        /// Number of levels in this source.
        public var depth: Int { levels.count }
        /// The leaf rung (the last level). Force-safe: `levels` is validated non-empty at init.
        public var leaf: Level { levels[levels.count - 1] }

        public init(levels: [Level], leafContentType: LeafContentType) {
            precondition(!levels.isEmpty, "SourceHierarchy must declare at least one level")
            self.levels = levels
            self.leafContentType = leafContentType
        }

        /// Convenience for the common flat shape: a single leaf level (e.g. swift-evolution
        /// proposals, swift-org articles).
        public static func flat(kind: String, leafContentType: LeafContentType = .markdown) -> SourceHierarchy {
            SourceHierarchy(levels: [Level(level: 1, kind: kind, isLeaf: true)], leafContentType: leafContentType)
        }

        /// Convenience for the framework -> leaf shape (e.g. apple-archive, hig).
        public static func framework(leafKind: String, leafContentType: LeafContentType = .markdown) -> SourceHierarchy {
            SourceHierarchy(
                levels: [
                    Level(level: 1, kind: "framework", isLeaf: false),
                    Level(level: 2, kind: leafKind, isLeaf: true),
                ],
                leafContentType: leafContentType
            )
        }
    }

    /// What a leaf document is, so the reader can render it natively. A string-backed enum: the
    /// wire form is the raw value, and an unknown value decodes to `.markdown` (the safe default)
    /// rather than failing, so a newer server can add a type without breaking older clients.
    public enum LeafContentType: String, Codable, Equatable, Sendable, CaseIterable {
        case markdown
        case image
        case pdf
        case code

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = LeafContentType(rawValue: raw) ?? .markdown
        }
    }
}
