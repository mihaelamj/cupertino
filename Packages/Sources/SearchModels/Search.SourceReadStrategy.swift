import Foundation
import LoggingModels

// MARK: - Search.SourceReadStrategy

extension Search {
    /// 2026-05-26 audit Finding #1055 (layer-2 follow-up to 14.3):
    /// per-source read strategy. Pre-fix `Services.ReadService` had a
    /// 3-bucket dispatch (`if source == .docs` / `.samples` /
    /// `.packages`) hardcoded inside `readFrom`. Adding a source with
    /// a new read backend required a new branch there.
    ///
    /// Post-fix each `<X>Source` target supplies a
    /// `Search.SourceReadStrategy` concrete and the CLI's read
    /// command dispatches through the provider. The shared
    /// `Search.DocsReadStrategy` concrete handles the 6 docs-tier
    /// sources (apple-docs / hig / apple-archive / swift-evolution /
    /// swift-org / swift-book); SampleCodeSource + PackagesSource
    /// each ship their own concrete.
    public protocol SourceReadStrategy: Sendable {
        /// Try to read the identifier as content from this source.
        /// Return nil when the identifier is not this source's
        /// concern (drives the auto-source fallback in
        /// `Services.ReadService`). Throw to surface a real error.
        func read(env: ReadEnvironment) async throws -> ReadResult?
    }

    /// Outcome of a successful read.
    public struct ReadResult: Sendable, Equatable {
        public let content: String
        /// Source-id of the provider that produced the content; lets
        /// callers (CLI / MCP) render "found in <X>" output.
        public let resolvedSourceID: String

        public init(content: String, resolvedSourceID: String) {
            self.content = content
            self.resolvedSourceID = resolvedSourceID
        }
    }

    /// Composition-root-supplied state a `SourceReadStrategy` needs.
    /// The CLI wires the 3 lookup strategies + the 3 DB URLs at
    /// command-handler time; per-source strategies pick out the
    /// fields they need and ignore the rest.
    public struct ReadEnvironment: Sendable {
        /// Identifier supplied by the user (URI or slug or
        /// owner/repo/path).
        public let identifier: String
        /// Output format the caller wants the content rendered in.
        public let format: DocumentFormat

        /// Per-source docs DB URLs (post-#1037 each docs-tier source
        /// owns its own file: hig.db / swift-evolution.db / etc.).
        /// Keyed by `SourceProvider.definition.id`. The shared
        /// `Search.DocsReadStrategy` picks the matching URL.
        public let docsDBURLs: [String: URL]
        /// Fallback search.db URL for callers that haven't migrated
        /// to the per-source map (pre-#1037 single-DB world + tests).
        public let fallbackSearchDB: URL
        /// Sample-code SQLite location.
        public let samplesDB: URL
        /// Packages SQLite location.
        public let packagesDB: URL

        /// Lookup strategy for docs-tier reads. CLI wires
        /// `Live`-prefixed concrete from `Services`.
        public let docsLookup: any DocsLookupStrategy
        /// Lookup strategy for sample-code reads.
        public let sampleLookup: any SampleLookupStrategy
        /// Lookup strategy for packages-file reads.
        public let packageFileLookup: any PackageFileLookupStrategy

        /// Allow auto-source flow to try other sources when this one
        /// returns nil. When false, the strategy MUST throw or
        /// resolve; nil is a hard miss. When true, returning nil
        /// signals "not my concern, try the next strategy".
        public let allowFallback: Bool

        public let logger: any LoggingModels.Logging.Recording

        public init(
            identifier: String,
            format: DocumentFormat,
            docsDBURLs: [String: URL],
            fallbackSearchDB: URL,
            samplesDB: URL,
            packagesDB: URL,
            docsLookup: any DocsLookupStrategy,
            sampleLookup: any SampleLookupStrategy,
            packageFileLookup: any PackageFileLookupStrategy,
            allowFallback: Bool,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.identifier = identifier
            self.format = format
            self.docsDBURLs = docsDBURLs
            self.fallbackSearchDB = fallbackSearchDB
            self.samplesDB = samplesDB
            self.packagesDB = packagesDB
            self.docsLookup = docsLookup
            self.sampleLookup = sampleLookup
            self.packageFileLookup = packageFileLookup
            self.allowFallback = allowFallback
            self.logger = logger
        }
    }

    // MARK: - Backend lookup protocols

    //
    // Each backend has its own protocol so the per-source read
    // strategy can ask only the part of the env it needs. The 3
    // protocols live in foundation (SearchModels) so per-source
    // targets can reference them without importing the producer
    // targets (SearchSQLite / SampleIndexSQLite / SearchAPI).
    // CLI's composition root wires `Live*` concretes that translate
    // each call into the real backend.

    public protocol DocsLookupStrategy: Sendable {
        /// Read a docs-tier URI's content. `searchDB` is the
        /// per-source DB URL the CLI resolved from the URI's scheme
        /// (or the fallback). Returns nil when the URI is not in
        /// this DB (404).
        func read(uri: String, format: DocumentFormat, searchDB: URL) async throws -> String?
    }

    public protocol SampleLookupStrategy: Sendable {
        /// Look up a sample project by id; returns nil when absent.
        func readProject(id: String, samplesDB: URL) async throws -> SampleProjectContent?
        /// Look up a file inside a sample project; returns nil when absent.
        func readFile(projectId: String, path: String, samplesDB: URL) async throws -> String?
    }

    /// Subset of a sample project's content surface the read path
    /// needs. Decouples per-source strategies from the heavier
    /// `Sample.Index.Project` value type in `SampleIndexModels`.
    public struct SampleProjectContent: Sendable, Equatable {
        public let readmeOrDescription: String

        public init(readmeOrDescription: String) {
            self.readmeOrDescription = readmeOrDescription
        }
    }

    public protocol PackageFileLookupStrategy: Sendable {
        /// Read a file inside a packages.db-indexed repo. Identifier
        /// is `<owner>/<repo>/<relpath>`. Returns nil when absent;
        /// throws on schema mismatch / open errors.
        func read(
            packagesDB: URL,
            owner: String,
            repo: String,
            path: String
        ) async throws -> String?
    }
}

// MARK: - Default extension

extension Search.SourceProvider {
    /// Default: no read capability. Sources whose content is
    /// readable through `cupertino read` override.
    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? { nil }
}
