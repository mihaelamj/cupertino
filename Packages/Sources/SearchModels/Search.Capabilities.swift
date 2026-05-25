import Foundation

// MARK: - Search.Capabilities

extension Search {
    /// What a source can answer at read time. Drives the CLI
    /// dispatcher's fan-out: a subcommand like `cupertino
    /// search-symbols` filters the production source registry to
    /// providers whose `capabilities.searchers` contains `.symbols`
    /// and only opens those DBs.
    ///
    /// Step 3 of the per-source DB split epic (see
    /// `docs/design/per-source-db-split.md`): each `SourceProvider`
    /// declares its capabilities matching the YAML manifest at
    /// `docs/sources/<sourceId>/manifest.yaml`. The Swift property is
    /// the runtime binding; the YAML is the human-readable contract
    /// reviewed at PR time + cross-checked by
    /// `scripts/check-source-manifests.sh`.
    ///
    /// Schema reference: `docs/design/corpus-structure.md` §3.5.
    public struct Capabilities: Sendable, Hashable {
        /// Which search modes this source's DB answers.
        public let searchers: Set<Searcher>

        /// Which non-search operations this source's DB answers.
        public let operations: Set<Operation>

        /// Typed feature flags about the rows (e.g.
        /// `hasMinPlatformVersion`, `hasFrameworkColumn`). Absent flags
        /// are treated as `false`. Keyed by the flag names documented
        /// in `corpus-structure.md` §3.5.3.
        public let metadata: [MetadataFlag: Bool]

        public init(
            searchers: Set<Searcher> = [],
            operations: Set<Operation> = [],
            metadata: [MetadataFlag: Bool] = [:]
        ) {
            self.searchers = searchers
            self.operations = operations
            self.metadata = metadata
        }

        /// Sentinel for sources that declare no capabilities. The
        /// dispatcher excludes these from every fan-out; useful as a
        /// protocol-level default so adding the property to the
        /// protocol isn't a breaking change for older conformers (each
        /// real source overrides with its own declared capabilities).
        public static let empty = Capabilities()

        // MARK: - Vocabulary

        /// Search mode. The CLI subcommand or MCP tool that uses each
        /// mode is documented at `corpus-structure.md` §3.5.1.
        public enum Searcher: String, Sendable, Hashable, CaseIterable {
            case text
            case symbols
            case propertyWrappers = "property-wrappers"
            case concurrency
            case conformances
            case generics
            case packageSearch = "package-search"
            case sampleFiles = "sample-files"
        }

        /// Non-search operation a source can answer. Documented at
        /// `corpus-structure.md` §3.5.2.
        public enum Operation: String, Sendable, Hashable, CaseIterable {
            case readByURI = "read-by-uri"
            case listFrameworks = "list-frameworks"
            case listSamples = "list-samples"
            case resolveRefs = "resolve-refs"
        }

        /// Typed feature flag. Documented at `corpus-structure.md`
        /// §3.5.3.
        public enum MetadataFlag: String, Sendable, Hashable, CaseIterable {
            case hasMinPlatformVersion
            case hasMinSwiftVersion
            case hasSampleCode
            case hasGenerics
            case hasDeprecationAttrs
            case hasAvailabilityAttrs
            case hasFrameworkColumn
            case hasProposalNumber
            case hasPackageMetadata
        }
    }
}

// MARK: - SourceProvider default

extension Search.SourceProvider {
    /// Default: no capabilities (dispatcher excludes from every
    /// fan-out). Per-source conformers override with their actual
    /// declared matrix. See `Search.Capabilities.empty`.
    public var capabilities: Search.Capabilities {
        .empty
    }
}
