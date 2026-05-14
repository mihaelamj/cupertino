import Foundation
import SharedConstants
import SharedModels

// MARK: - Search.MarkdownToStructuredPage

/// Closure shape for converting raw markdown (with optional YAML / TOML
/// front-matter) into a `Shared.Models.StructuredDocumentationPage`.
///
/// The Search target's strategies (`AppleDocsStrategy`, `SwiftOrgStrategy`)
/// take one of these at init so they can parse markdown pages without
/// directly depending on the `CoreJSONParser` target where the concrete
/// `Core.JSONParser.MarkdownToStructuredPage.convert(_:url:)` lives.
///
/// The composition root (the CLI binary, the Indexer service entry
/// point, or a test harness) supplies the concrete function. Indexing
/// callers that don't need markdown→structured conversion can pass a
/// stub that always returns `nil`; the strategies that don't call the
/// closure (HIG, Archive, SampleCode, SwiftPackages) won't invoke it.
///
/// Mirrors the `Search.Database` / `Sample.Index.Reader` / `MakeSearchDatabase`
/// pattern: the abstraction lives in a value-types target, the
/// implementation lives in the producer target, the wiring lives at the
/// composition root.
public extension Search {
    typealias MarkdownToStructuredPage = @Sendable (
        _ markdown: String,
        _ url: URL?
    ) -> Shared.Models.StructuredDocumentationPage?
}
