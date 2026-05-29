import Foundation

extension AppleConstraintsKit {
    /// Minimal `Decodable` projection of Apple's symbol-graph JSON
    /// (as emitted by `swift symbolgraph-extract`). Only the fields
    /// the constraint pipeline reads are declared; the rest is
    /// dropped at decode time.
    ///
    /// **Why a hand-rolled schema rather than `swift-docc-symbolkit`.**
    /// (a) Adds a network dependency to a project the user has asked
    /// to keep deps tight. (b) `SymbolKit`'s model is exhaustive
    /// (hundreds of fields covering availability, source ranges,
    /// declaration fragments, etc.) which we'd drop on the floor.
    /// (c) Symbol-graph files are 456 MB for SwiftUI alone; decoding
    /// only what we need (`pathComponents`, `kind.identifier`,
    /// `swiftGenerics.constraints`) keeps the parse fast and the
    /// extractor focused. (d) Matches the project memory rule
    /// `feedback_prefer_hand_rolled.md`.
    ///
    /// The shape mirrors the upstream JSON layout exactly. Extending
    /// later (e.g. to pull in `availability` per #225 cross-fix) is
    /// adding a `Decodable` property to the matching nested struct;
    /// no schema migration needed since fields outside the model are
    /// ignored.
    public enum SymbolGraph {
        /// Top-level document. One per `swift symbolgraph-extract`
        /// emitted file. There are typically several per Apple
        /// framework. the canonical `<Module>.symbols.json` plus
        /// `<Module>@<OtherModule>.symbols.json` for cross-module
        /// extensions (e.g. `SwiftUI@Foundation.symbols.json` carries
        /// extensions SwiftUI adds to Foundation types).
        public struct Document: Decodable, Sendable {
            public let module: Module
            public let symbols: [Symbol]
            /// Top-level relationship edges (`conformsTo` / `inheritsFrom` /
            /// `memberOf` / ...). Optional so the constraints-only path and
            /// trivial extension files with no relationships decode unchanged.
            public let relationships: [Relationship]?

            public init(module: Module, symbols: [Symbol], relationships: [Relationship]? = nil) {
                self.module = module
                self.symbols = symbols
                self.relationships = relationships
            }
        }

        /// Module declaration. We use `name` to construct the
        /// `apple-docs://<framework>/...` URI prefix.
        public struct Module: Decodable, Sendable {
            public let name: String

            public init(name: String) {
                self.name = name
            }
        }

        /// One symbol entry. We only read fields the URI mapper +
        /// constraint extractor need.
        public struct Symbol: Decodable, Sendable {
            public let pathComponents: [String]
            public let kind: Kind
            public let swiftGenerics: SwiftGenerics?
            /// Stable Unique Symbol Reference (`identifier.precise`, e.g.
            /// `s:7SwiftUI4ViewP`). Optional so existing constraints-only
            /// fixtures that omit it still decode. The conformance extractor
            /// uses it to resolve a relationship's `source`/`target` USR back
            /// to a symbol's `pathComponents`.
            public let identifier: Identifier?

            public init(
                pathComponents: [String],
                kind: Kind,
                swiftGenerics: SwiftGenerics? = nil,
                identifier: Identifier? = nil
            ) {
                self.pathComponents = pathComponents
                self.kind = kind
                self.swiftGenerics = swiftGenerics
                self.identifier = identifier
            }
        }

        /// Stable symbol identity. We read only `precise` (the USR);
        /// `interfaceLanguage` and the rest are dropped at decode.
        public struct Identifier: Decodable, Sendable {
            public let precise: String

            public init(precise: String) {
                self.precise = precise
            }
        }

        /// One relationship edge from the symbol-graph's top-level
        /// `relationships` array. `source` / `target` are USRs; the
        /// conformance extractor resolves `source` to a `pathComponents`
        /// path (this module's symbols) and prefers `targetFallback` (the
        /// display name, e.g. `"SwiftUICore.View"`) for the protocol name,
        /// since `target` often points at another module not in this file.
        public struct Relationship: Decodable, Sendable {
            public let kind: String
            public let source: String
            public let target: String
            public let targetFallback: String?

            public init(kind: String, source: String, target: String, targetFallback: String? = nil) {
                self.kind = kind
                self.source = source
                self.target = target
                self.targetFallback = targetFallback
            }

            /// True for the structural edges the conformance graph keeps:
            /// `conformsTo` (T : SomeProtocol) and `inheritsFrom`
            /// (class : Superclass). `memberOf` and the rest are dropped.
            public var contributesToConformanceGraph: Bool {
                kind == "conformsTo" || kind == "inheritsFrom"
            }
        }

        /// Symbol kind tag. `swift.struct`, `swift.class`,
        /// `swift.protocol`, `swift.func`, `swift.method`,
        /// `swift.init`, `swift.subscript`, `swift.typealias`,
        /// `swift.enum`, `swift.actor`, etc. Drives the extractor's
        /// kind-filter (e.g. drop `swift.var` since properties never
        /// carry generic constraints directly).
        public struct Kind: Decodable, Sendable {
            public let identifier: String

            public init(identifier: String) {
                self.identifier = identifier
            }
        }

        /// `swiftGenerics` block on a symbol. Optional because most
        /// symbols (every non-generic function / property / enum
        /// case) lack one entirely.
        public struct SwiftGenerics: Decodable, Sendable {
            public let constraints: [Constraint]?

            public init(constraints: [Constraint]? = nil) {
                self.constraints = constraints
            }
        }

        /// One generic-constraint entry. Apple's symbol-graph emits
        /// three `kind` values we observe in practice:
        /// - `"conformance"`. `T : SomeProtocol`. The constraint
        ///   shape `search_generics` answers.
        /// - `"superclass"`. `T : SomeClass`. Class-bound generics;
        ///   we treat as a conformance for search purposes.
        /// - `"sameType"`. `T == U`. Same-type requirement, NOT a
        ///   protocol-conformance constraint; excluded from the
        ///   constraint search axis (matches the iter-1 AST
        ///   extractor's behaviour).
        ///
        /// `lhs` is the type-parameter name; `rhs` is the constraining
        /// type. The pipeline keeps `rhs` (the constraint half) and
        /// joins them comma-separated for the
        /// `doc_symbols.generic_constraints` blob.
        public struct Constraint: Decodable, Sendable {
            public let kind: String
            public let lhs: String
            public let rhs: String

            public init(kind: String, lhs: String, rhs: String) {
                self.kind = kind
                self.lhs = lhs
                self.rhs = rhs
            }

            /// True when this constraint contributes to the
            /// `generic_constraints` blob. Conformance + superclass
            /// both qualify; sameType is the carve-out.
            public var contributesToSearchAxis: Bool {
                kind == "conformance" || kind == "superclass"
            }
        }
    }
}
