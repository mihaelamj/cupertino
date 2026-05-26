import Foundation

// MARK: - Shared.Models.CorpusManifest

/// Declarative shape of a source's repo-side `manifest.yaml` declaration
/// at `docs/sources/<source-id>/manifest.yaml`. Each source ships one,
/// reviewed at PR time, never written at runtime. This type is the
/// Codable contract; it sits in the foundation-only Models tier so any
/// producer / composition root can hold a parsed manifest without
/// dragging the concrete source targets in.
///
/// **Status (2026-05-25, step 2 of the per-source DB split epic):** this
/// type lands as a contract; no Swift code parses the YAML at runtime
/// yet. The YAML files exist for human review + CI cross-check (via
/// `scripts/check-source-manifests.sh`, shell + yq). Step 3 of the epic
/// wires a YAML loader (Yams dependency, decision pending in
/// `docs/design/corpus-structure.md` §8). When that loader lands, this
/// type is what it decodes into.
///
/// Schema reference: `docs/design/corpus-structure.md` §3.
///
/// Identifier discipline reminder (per
/// `Shared.Models.DatabaseDescriptor` per-source comment block): the
/// `destinationDB` field carries a `DatabaseDescriptor.id` value
/// (e.g. `apple-documentation`), NOT a `Shared.Constants.SourcePrefix`
/// value. The `sourceId` field carries the canonical source id (the
/// row-emission tag where SourceProvider.definition.id and the manifest
/// agree). The two fields are deliberately separate naming spaces; the
/// binding from one to the other is via the source provider's
/// `destinationDB` property in code, never via string matching at
/// runtime.
extension Shared.Models {
    public struct CorpusManifest: Codable, Sendable, Hashable {
        // MARK: - Required top-level fields

        /// Canonical source id. MUST match
        /// `Search.SourceProvider.definition.id` for the source whose
        /// manifest this is. CI's `check-source-manifests.sh` enforces
        /// the match against the production registry.
        public let sourceId: String

        /// Human-readable display name (used by `cupertino doctor`'s
        /// per-source section and the MCP server's tool-availability
        /// advertisement).
        public let displayName: String

        /// On-disk folder name under the corpus root (typically
        /// `~/.cupertino-dev/corpus/`). Convention: equals `sourceId`.
        /// The CI script enforces the convention.
        public let corpusFolder: String

        /// Canonical `DatabaseDescriptor.id` of the DB this source's
        /// rows land in. Currently one of: `apple-documentation`, `hig`,
        /// `apple-archive`, `swift-evolution`, `swift-documentation`,
        /// `apple-sample-code`, `swift-packages` (plus the deprecated
        /// `search` / `samples` / `packages` during the migration arc).
        public let destinationDB: String

        /// How the fetcher acquires content for this source.
        public let fetcher: Fetcher

        /// How the indexer walks the corpus folder.
        public let indexer: Indexer

        /// What this source can answer at read time (drives CLI
        /// dispatcher fan-out + MCP tool-availability advertisement +
        /// `cupertino doctor` per-source section). See
        /// `docs/design/corpus-structure.md` §3.5 for the full vocabulary.
        public let capabilities: Capabilities

        // MARK: - Optional top-level fields

        /// Multi-line human description (rendered by `cupertino doctor`
        /// and the dashboard).
        public let description: String?

        /// View-source companions (sources whose rows are emitted into
        /// THIS source's DB by THIS source's strategy). Today the only
        /// view-source pairing is swift-book inside swift-documentation;
        /// see `Shared.Models.DatabaseDescriptor.swiftDocumentation`.
        public let viewSources: [ViewSource]?

        /// Freshness policy (drives `cupertino doctor` staleness
        /// warnings + the recrawl scheduler).
        public let snapshotPolicy: SnapshotPolicy?

        /// Search-time properties (per-source ranking weights).
        public let searchProperties: SearchProperties?

        // MARK: - Nested types

        /// Fetcher descriptor. `kind` selects the fetch family
        /// (`apple-docs-api`, `git-clone`, `http-archive`, `github-api`,
        /// `file-bundle`); per-kind options live in `options` as a
        /// `[String: String]` map. String-valued options are sufficient
        /// for every fetcher today (URL, request delay encoded as a
        /// numeric string, etc.); avoiding an `AnyCodable` polymorphic
        /// type keeps the foundation-tier model dependency-free. Step 3
        /// introduces per-kind typed views over the same data when the
        /// loader wires up. Matches the YAML schema in
        /// `docs/design/corpus-structure.md` §3 verbatim (key name +
        /// shape), so a step-3 YAML loader can decode without translation.
        public struct Fetcher: Codable, Sendable, Hashable {
            public let kind: String
            public let options: [String: String]?

            public init(kind: String, options: [String: String]? = nil) {
                self.kind = kind
                self.options = options
            }
        }

        /// Indexer descriptor. The extractor field references a Swift
        /// type by fully-qualified name; the actual binding at index
        /// time is via the source's `makeIndexer()` return value (the
        /// manifest's extractor field is a human-readable cross-check,
        /// not the binding).
        public struct Indexer: Codable, Sendable, Hashable {
            public let fileGlobs: [String]
            public let entryPoints: [String]?
            public let excludes: [String]?
            public let extractor: String

            public init(
                fileGlobs: [String],
                entryPoints: [String]? = nil,
                excludes: [String]? = nil,
                extractor: String
            ) {
                self.fileGlobs = fileGlobs
                self.entryPoints = entryPoints
                self.excludes = excludes
                self.extractor = extractor
            }
        }

        /// View-source companion descriptor (see swift-book in
        /// swift-documentation.db).
        public struct ViewSource: Codable, Sendable, Hashable {
            public let id: String
            public let urlPrefix: String?

            public init(id: String, urlPrefix: String? = nil) {
                self.id = id
                self.urlPrefix = urlPrefix
            }
        }

        /// Freshness policy.
        public struct SnapshotPolicy: Codable, Sendable, Hashable {
            public let staleAfterDays: Int?
            public let refetchOn: [String]?

            public init(staleAfterDays: Int? = nil, refetchOn: [String]? = nil) {
                self.staleAfterDays = staleAfterDays
                self.refetchOn = refetchOn
            }
        }

        /// Per-source search-time properties.
        public struct SearchProperties: Codable, Sendable, Hashable {
            public let searchQuality: Double?
            public let intentDefault: String?
            public let rankWeight: Double?

            public init(
                searchQuality: Double? = nil,
                intentDefault: String? = nil,
                rankWeight: Double? = nil
            ) {
                self.searchQuality = searchQuality
                self.intentDefault = intentDefault
                self.rankWeight = rankWeight
            }
        }

        /// Capability declaration (per
        /// `docs/design/corpus-structure.md` §3.5). The CLI dispatcher
        /// reads these to gate which DBs receive a query.
        public struct Capabilities: Codable, Sendable, Hashable {
            /// Which search modes this DB answers (e.g. `text`,
            /// `symbols`, `property-wrappers`, `concurrency`,
            /// `conformances`, `generics`, `package-search`,
            /// `sample-files`).
            public let searchers: [String]

            /// Which non-search operations this DB answers (e.g.
            /// `read-by-uri`, `list-frameworks`, `list-samples`,
            /// `resolve-refs`).
            public let operations: [String]

            /// Typed feature flags (`hasMinPlatformVersion`,
            /// `hasMinSwiftVersion`, `hasSampleCode`, `hasGenerics`,
            /// `hasDeprecationAttrs`, `hasAvailabilityAttrs`,
            /// `hasFrameworkColumn`, `hasProposalNumber`,
            /// `hasPackageMetadata`). Absent flags are `false` by
            /// default; only true flags appear in each manifest.
            /// A manifest with no metadata key at all is legal: the
            /// custom `init(from:)` below defaults the field to `[:]`
            /// when the JSON / YAML omits it (Swift's `= [:]` init
            /// default does not apply to Codable's synthesized init).
            public let metadata: [String: Bool]

            public init(
                searchers: [String],
                operations: [String],
                metadata: [String: Bool] = [:]
            ) {
                self.searchers = searchers
                self.operations = operations
                self.metadata = metadata
            }

            private enum CodingKeys: String, CodingKey {
                case searchers
                case operations
                case metadata
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                searchers = try container.decode([String].self, forKey: .searchers)
                operations = try container.decode([String].self, forKey: .operations)
                metadata = try container.decodeIfPresent([String: Bool].self, forKey: .metadata) ?? [:]
            }
        }

        // MARK: - Public init

        public init(
            sourceId: String,
            displayName: String,
            corpusFolder: String,
            destinationDB: String,
            fetcher: Fetcher,
            indexer: Indexer,
            capabilities: Capabilities,
            description: String? = nil,
            viewSources: [ViewSource]? = nil,
            snapshotPolicy: SnapshotPolicy? = nil,
            searchProperties: SearchProperties? = nil
        ) {
            self.sourceId = sourceId
            self.displayName = displayName
            self.corpusFolder = corpusFolder
            self.destinationDB = destinationDB
            self.fetcher = fetcher
            self.indexer = indexer
            self.capabilities = capabilities
            self.description = description
            self.viewSources = viewSources
            self.snapshotPolicy = snapshotPolicy
            self.searchProperties = searchProperties
        }
    }
}
