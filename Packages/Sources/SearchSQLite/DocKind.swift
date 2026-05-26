// DocKind.swift
//
// High-level taxonomy for every row in `docs_metadata` (#192 section C1).
// Stored as `docs_metadata.kind TEXT NOT NULL DEFAULT 'unknown'`. Consumed by
// the smart-query wrapper in section E to route queries per-intent.
//
// The taxonomy is deterministic: a pure function of `source`,
// `structuredKind`, and URI path. No AI, no runtime state.
//
// Reserved but not yet produced (sources pending in Epic #190):
//   - wwdcTranscript (WWDC session transcripts, #58)
//   - swiftForumsThread (Swift Forums discussions, #89)
//   - externalLibraryDoc (SQLite/Redis/etc. third-party docs, #116)
// When one of those sources lands, add a switch case to `Classify.kind(...)`
// and a corresponding case to `DocKind`.

import Foundation
import SearchModels
import SharedConstants

extension Search {
    /// Deterministic classifier for `DocKind`. Pure; safe to call from any context.
    ///
    /// **Post-#1045 Gap 3**: dispatches via the supplied
    /// `Search.SourceLookup` to each registered provider's
    /// `docKind(structuredKind:uriPath:)` method. The 6-arm
    /// `switch source` is gone; new sources contribute their
    /// classifier inside their per-source target. Sources without a
    /// registered provider fall through to `.unknown`.
    public enum Classify {
        /// Classify a document given its source prefix, optional structured-doc kind,
        /// and URI path. See #192 section C1 for the full spec.
        ///
        /// - Parameters:
        ///   - source: `docs_metadata.source` (e.g. `"apple-docs"`, `"swift-evolution"`).
        ///   - structuredKind: the `StructuredDocumentationPage.Kind` raw value when
        ///     available (for `apple-docs` pages that went through the structured
        ///     decoder). `nil` for sources that don't produce structured pages.
        ///   - uriPath: the URI path component (e.g. `/documentation/swiftui/view` or
        ///     `/samplecode/swiftui/robust-nav`). Used to disambiguate sample-code
        ///     pages which share `source == apple-docs` with symbol pages.
        ///   - lookup: the production source lookup. When supplied, dispatches
        ///     via each provider's `docKind(...)` method. When nil (legacy
        ///     callers), falls back to the registry-free static map preserved
        ///     for back-compat.
        public static func kind(
            source: String,
            structuredKind: String? = nil,
            uriPath: String = "",
            lookup: Search.SourceLookup? = nil
        ) -> Search.DocKind {
            if let lookup, let provider = lookup.provider(for: source) {
                return provider.docKind(structuredKind: structuredKind, uriPath: uriPath)
            }
            return Self.fallbackKind(
                source: source,
                structuredKind: structuredKind,
                uriPath: uriPath
            )
        }

        /// Back-compat fallback used when no `SourceLookup` is in scope.
        /// Mirrors the pre-#1045 hardcoded `switch source` — kept for
        /// callers that haven't migrated to threading a registry
        /// through. New sources won't appear here; they MUST be passed
        /// via the `lookup:` parameter to be classified correctly.
        private static func fallbackKind(
            source: String,
            structuredKind: String?,
            uriPath: String
        ) -> Search.DocKind {
            switch source {
            case Shared.Constants.SourcePrefix.swiftEvolution:
                return .evolutionProposal
            case Shared.Constants.SourcePrefix.swiftBook:
                return .swiftBook
            case Shared.Constants.SourcePrefix.swiftOrg:
                return .swiftOrgDoc
            case Shared.Constants.SourcePrefix.hig:
                return .hig
            case Shared.Constants.SourcePrefix.appleArchive:
                return .archive
            case Shared.Constants.SourcePrefix.appleDocs:
                return classifyAppleDocs(structuredKind: structuredKind, uriPath: uriPath)
            default:
                return .unknown
            }
        }

        /// Apple-docs structured-kind classifier. Public so per-source
        /// `Search.SourceProvider.docKind(...)` overrides in AppleDocsSource
        /// can call it without duplicating the mapping logic.
        public static func classifyAppleDocs(
            structuredKind: String?,
            uriPath: String
        ) -> Search.DocKind {
            // URI-based override: sample-code landing pages share `apple-docs` source
            // but should be routed like code examples, not symbol references.
            if uriPath.lowercased().contains("/samplecode/") {
                return .sampleCode
            }

            // Map `StructuredDocumentationPage.Kind` raw values to the coarser taxonomy.
            // Unknown or missing structured kinds fall through to `.unknown`.
            // #626 — `case`, `initializer`, `subscript`, `actor` are
            // declaration members / type-shapes that all index as
            // `.symbolPage` in the coarser taxonomy. `sample code` is
            // its own bucket.
            switch structuredKind {
            case "protocol", "class", "struct", "enum", "actor",
                 "function", "property", "method", "operator",
                 "typealias", "macro", "framework",
                 "case", "initializer", "subscript":
                return .symbolPage
            case "article", "collection":
                return .article
            case "tutorial":
                return .tutorial
            case "sample code":
                return .sampleCode
            default:
                return .unknown
            }
        }
    }
}
