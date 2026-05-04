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
import Shared

extension Search {
    /// High-level document-shape taxonomy stored per row in `docs_metadata`.
    public enum DocKind: String, Codable, Sendable, CaseIterable {
        /// API reference with a declaration (struct/class/protocol/enum/func/etc.).
        case symbolPage
        /// Discussion, overview, or collection index page.
        case article
        /// DocC tutorial chapter or step.
        case tutorial
        /// Apple sample-code landing page.
        case sampleCode
        /// Swift Evolution proposal.
        case evolutionProposal
        /// The Swift Programming Language book.
        case swiftBook
        /// Other Swift.org documentation.
        case swiftOrgDoc
        /// Human Interface Guidelines page.
        case hig
        /// Legacy Apple Archive programming guide.
        case archive
        /// Fallback — classifier had no matching branch.
        case unknown
    }

    /// Deterministic classifier for `DocKind`. Pure; safe to call from any context.
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
        public static func kind(
            source: String,
            structuredKind: String? = nil,
            uriPath: String = ""
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

        private static func classifyAppleDocs(
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
            switch structuredKind {
            case "protocol", "class", "struct", "enum",
                 "function", "property", "method", "operator",
                 "typealias", "macro", "framework":
                return .symbolPage
            case "article", "collection":
                return .article
            case "tutorial":
                return .tutorial
            default:
                return .unknown
            }
        }
    }
}
