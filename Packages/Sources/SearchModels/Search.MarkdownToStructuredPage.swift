import Foundation
import SharedConstants
import SharedModels

// MARK: - Search.MarkdownToStructuredPageStrategy

/// Strategy for converting raw markdown (with optional YAML / TOML
/// front-matter) into a `Shared.Models.StructuredDocumentationPage`.
/// GoF Strategy pattern (Gamma et al, 1994): a family of algorithms
/// (one production parser, many test stubs) interchangeable behind a
/// named protocol.
///
/// The Search target's strategies (`AppleDocsStrategy`,
/// `SwiftOrgStrategy`) accept a conformer at init so they can parse
/// markdown pages without directly depending on the `CoreJSONParser`
/// target where the concrete
/// `Core.JSONParser.MarkdownToStructuredPage.convert(_:url:)` lives.
///
/// The composition root (the CLI binary, the Indexer service entry
/// point, or a test harness) supplies the concrete conformer. Indexing
/// callers that don't need markdown→structured conversion can pass a
/// stub that always returns `nil`; the strategies that don't call the
/// converter (HIG, Archive, SampleCode, SwiftPackages) won't invoke
/// it.
///
/// This replaces the previous
/// `Search.MarkdownToStructuredPage = @Sendable (String, URL?) -> Page?`
/// closure typealias. The protocol form names the contract at the
/// constructor site (`markdownStrategy: any Search.MarkdownToStructuredPageStrategy`),
/// makes captured-state surface explicit on the conforming type's
/// stored properties, and produces one-line test mocks instead of
/// captured-throw closures.
public extension Search {
    protocol MarkdownToStructuredPageStrategy: Sendable {
        /// Convert raw markdown + an optional originating URL into a
        /// structured documentation page. Returns `nil` when the
        /// markdown can't be parsed (malformed front-matter, empty
        /// body, etc.) — the caller decides whether that's fatal.
        func convert(markdown: String, url: URL?) -> Shared.Models.StructuredDocumentationPage?
    }
}
