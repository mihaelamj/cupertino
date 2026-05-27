import Foundation
import SharedConstants

// MARK: - Search.IndexWriter

extension Search {
    /// Write-side seam for the search-index database.
    ///
    /// Production implementation: `Search.Index` (the actor in the
    /// SearchAPI SPM target). Consumers ( `Search.IndexBuilder`, the 6
    /// source-indexing strategies, the indexer-side CLI runner ) accept
    /// this protocol instead of taking a behavioural dependency on the
    /// concrete SearchAPI target.
    ///
    /// Mirrors the existing `Search.Database` seam in `SearchModels`,
    /// which covers the READ surface of the same `Search.Index` actor.
    /// `Search.Database` + `Search.IndexWriter` together cover every
    /// public method on `Search.Index` that is called from OUTSIDE the
    /// SearchAPI target. A handful of Search-internal-only write methods
    /// (`indexItem`, `indexItems`, `indexPackage`) are not on either
    /// protocol because no external caller needs them today; if a
    /// future consumer outside the SearchAPI target needs one, lift it
    /// onto `Search.IndexWriter` then.
    ///
    /// The protocol carries 10 write methods: `indexDocument`,
    /// `indexStructuredDocument`, `indexSampleCode`, `indexCodeExamples`,
    /// `extractCodeExampleSymbols`, `updateFrameworkSynonyms`,
    /// `applyAppleStaticConstraints`, `propagateConstraintsFromParents`,
    /// `clearIndex`, plus `registerFrameworkAlias` (no external production
    /// caller today; exposed on the protocol so tests can pre-register
    /// canonical names before driving the indexer). Lifecycle
    /// (`disconnect`) is already on `Search.Database` and is not
    /// re-declared here.
    ///
    /// Added by epic #893's child #896. The rewire of `Search.IndexBuilder`
    /// + the 6 strategies to consume `any Search.IndexWriter` via init
    /// lands separately under child #897.
    public protocol IndexWriter: Sendable {
        /// Index one document via the unified parameter bundle. The
        /// `Search.IndexDocumentParams` struct groups the 18 underlying
        /// indexer fields so call sites stay readable.
        func indexDocument(_ params: Search.IndexDocumentParams) async throws

        /// Index a `Shared.Models.StructuredDocumentationPage` produced
        /// by the JSON parser. Internally bridges to `indexDocument`
        /// after extracting optimised FTS content from the structured
        /// page (kind-aware extraction so symbols / articles / sample
        /// pages each get focused content rather than the full member
        /// table dump).
        func indexStructuredDocument(
            uri: String,
            source: String,
            framework: String,
            page: Shared.Models.StructuredDocumentationPage,
            jsonData: String,
            overrideMinIOS: String?,
            overrideMinMacOS: String?,
            overrideMinTvOS: String?,
            overrideMinWatchOS: String?,
            overrideMinVisionOS: String?,
            overrideAvailabilitySource: String?,
            implementationSwiftVersion: String?
        ) async throws

        // The concrete `Search.Index.indexStructuredDocument` carries
        // `= nil` defaults on `overrideMinIOS` ... `implementationSwiftVersion`.
        // Swift protocol method declarations cannot carry default
        // parameter values, so existing strategy call sites
        // (`Search.Strategies.SwiftEvolution`, `Search.Strategies.HIG`,
        // others) rely on those defaults. The convenience extension on
        // this protocol (immediately below the `protocol` block)
        // reproduces the default-shape so the #897 rewire of the
        // strategies' `indexItems(into index:)` parameter from
        // `Search.Index` to `any Search.Database & Search.IndexWriter`
        // does not force every call site to pass all 12 arguments
        // explicitly.

        /// Index one Apple sample-code project into both the FTS table
        /// and the structured `sample_code_metadata` table. Called by
        /// the SampleCode strategy with one row per `.zip` in the
        /// catalog.
        func indexSampleCode(
            url: String,
            framework: String,
            title: String,
            description: String,
            zipFilename: String,
            webURL: String,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?
        ) async throws

        /// Replace the `doc_code_examples` rows for a given document URI
        /// with the supplied list. Strategies call this after the parent
        /// structured-document indexing pass; the example list is
        /// extracted from the structured page's code blocks.
        func indexCodeExamples(
            docUri: String,
            codeExamples: [(code: String, language: String)]
        ) async throws

        /// Extract symbols + imports from the Swift-language code
        /// examples on a page and append them to `doc_symbols` /
        /// `doc_imports`. Called after `indexStructuredDocument` (which
        /// owns the clear), so this method only ADDs code-example
        /// findings on top of the declaration-derived symbols.
        func extractCodeExampleSymbols(
            docUri: String,
            codeExamples: [(code: String, language: String)]
        ) async throws

        /// Register a `framework_aliases` row binding a slug to a
        /// canonical display name. Today the only production caller is
        /// `Search.Index.indexStructuredDocument` internally when a
        /// page's `module` field is set; exposed on the protocol so
        /// tests can pre-register canonical names before driving the
        /// indexer.
        func registerFrameworkAlias(
            identifier: String,
            displayName: String
        ) async throws

        /// Update the `synonyms` column on a `framework_aliases` row.
        /// Called by the IndexBuilder during the post-index synonyms
        /// pass, and by the `Enrichment.SynonymsPass` enrichment runner.
        func updateFrameworkSynonyms(
            identifier: String,
            synonyms: String
        ) async throws

        /// Run the Apple static-constraints enrichment pass. Iterates
        /// `Search.StaticConstraintsLookup` entries and applies the
        /// `generic_constraints` column updates to matching
        /// `doc_symbols` rows. Idempotent.
        ///
        /// Returns the affected-row count summed across both the exact
        /// match and hash-prefix UPDATE statements. Zero when `lookup`
        /// is nil, the entries list is empty, or no row matched.
        @discardableResult
        func applyAppleStaticConstraints(
            lookup: (any Search.StaticConstraintsLookup)?,
            audit: (any Search.EnrichmentAuditObserver)?,
            dbPath: String
        ) async throws -> Int

        /// Run the hierarchy-derived constraint propagation pass. Walks
        /// the indexed inheritance edges and propagates parent
        /// constraints onto descendants where the child symbol has no
        /// direct constraint entry. Idempotent.
        ///
        /// Returns the count of child rows whose `generic_constraints`
        /// were filled in from a parent. Zero when no parent rows
        /// carried constraints or no child row qualified for inheritance.
        @discardableResult
        func propagateConstraintsFromParents(
            audit: (any Search.EnrichmentAuditObserver)?,
            dbPath: String
        ) async throws -> Int

        /// HIG-specific topic-aware platform inference (#1073). For
        /// rows whose URI declares an explicit platform target
        /// (designing-for-watchos, spatial-layout, mac-catalyst,
        /// carplay, etc.), NULLs the `min_<platform>` columns for
        /// non-applicable platforms. Rows without an explicit
        /// platform keyword keep their cross-platform defaults.
        ///
        /// Idempotent.  Returns the count of rows whose columns
        /// were updated.
        @discardableResult
        func applyHIGPlatformInference(
            audit: (any Search.EnrichmentAuditObserver)?,
            dbPath: String
        ) async throws -> Int

        /// Drop every row from every search-index table. Used by
        /// `IndexBuilder.buildIndex` when `--clear` is passed and by
        /// the `save --force-replace` recovery flag. Schema rows
        /// remain; only data is purged.
        func clearIndex() async throws
    }
}

// MARK: - Search.IndexWriter convenience defaults

// IMPORTANT: the two convenience overloads below forward into the
// protocol's primary requirement of the same name. When a conformer
// provides a witness for the 12-/11-argument primary (the production
// `Search.Index` witness does; see `Search.Index.IndexWriter.swift`),
// Swift's overload resolution dispatches the extension's inner call
// to the witness and there is no recursion. When a conformer relies
// on this extension AS its only implementation (i.e. declares
// conformance without implementing the 12-/11-arg primary), the inner
// call routes back into the extension and the method recurses
// forever. Production code is safe (Search.Index provides both
// witnesses). Test stubs / mocks conforming to `Search.IndexWriter`
// MUST implement the full-arity primary methods, not rely on these
// defaults.
//
// Activated by #897 (the rewire of `Search.IndexBuilder` + the 6
// concrete strategies to receive `any Search.Database & Search.IndexWriter`
// via init). Strategies whose existing call sites pass fewer than the
// full primary-requirement arity (`Search.Strategies.SwiftEvolution`,
// `Search.Strategies.HIG`, etc.) reach these convenience defaults
// through the composed-existential dispatch path. Pre-#897 (i.e. on
// `develop` after #911 / #896 landed and before #897), these defaults
// existed but were unreachable because the strategies still took the
// concrete `Search.Index` directly and dispatched into the actor's
// `= nil` defaults.

public extension Search.IndexWriter {
    /// Convenience overload that defaults every optional override
    /// parameter to `nil`. Mirrors the existing `Search.Index.indexStructuredDocument`
    /// concrete shape (which carries `= nil` defaults on the 7 override
    /// parameters), so strategy call sites that pass fewer than 12
    /// arguments today (`Search.Strategies.SwiftEvolution`, `Search.Strategies.HIG`,
    /// etc.) will keep compiling once #897 rewires them onto
    /// `any Search.IndexWriter`. Forwards every argument to the
    /// protocol's primary requirement.
    func indexStructuredDocument(
        uri: String,
        source: String,
        framework: String,
        page: Shared.Models.StructuredDocumentationPage,
        jsonData: String,
        overrideMinIOS: String? = nil,
        overrideMinMacOS: String? = nil,
        overrideMinTvOS: String? = nil,
        overrideMinWatchOS: String? = nil,
        overrideMinVisionOS: String? = nil,
        overrideAvailabilitySource: String? = nil,
        implementationSwiftVersion: String? = nil
    ) async throws {
        try await indexStructuredDocument(
            uri: uri,
            source: source,
            framework: framework,
            page: page,
            jsonData: jsonData,
            overrideMinIOS: overrideMinIOS,
            overrideMinMacOS: overrideMinMacOS,
            overrideMinTvOS: overrideMinTvOS,
            overrideMinWatchOS: overrideMinWatchOS,
            overrideMinVisionOS: overrideMinVisionOS,
            overrideAvailabilitySource: overrideAvailabilitySource,
            implementationSwiftVersion: implementationSwiftVersion
        )
    }

    /// Convenience overload that defaults the 5 `min*` platform-version
    /// parameters to `nil`. Mirrors the existing
    /// `Search.Index.indexSampleCode` concrete shape (which carries
    /// `= nil` defaults on the 5 `min*` parameters) so the SampleCode
    /// strategy keeps compiling after #897 rewires it onto
    /// `any Search.IndexWriter`. Forwards every argument to the
    /// protocol's primary requirement.
    func indexSampleCode(
        url: String,
        framework: String,
        title: String,
        description: String,
        zipFilename: String,
        webURL: String,
        minIOS: String? = nil,
        minMacOS: String? = nil,
        minTvOS: String? = nil,
        minWatchOS: String? = nil,
        minVisionOS: String? = nil
    ) async throws {
        try await indexSampleCode(
            url: url,
            framework: framework,
            title: title,
            description: description,
            zipFilename: zipFilename,
            webURL: webURL,
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS
        )
    }
}
