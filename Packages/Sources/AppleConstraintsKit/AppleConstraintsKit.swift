import Foundation

/// Namespace anchor for the `AppleConstraintsKit` SPM target.
///
/// `AppleConstraintsKit` is the producer-side companion to the
/// `Search.StaticConstraintsLookup` protocol seam (declared in
/// `SearchModels`). It carries the parser, URI mapper, and Codable
/// table format for the authoritative Apple-type generic-constraints
/// table derived from `swift symbolgraph-extract` output.
///
/// **What's in this target.**
/// - `AppleConstraintsKit.SymbolGraph`: minimal `Decodable` schema
///   for the upstream symbol-graph JSON. Only the fields the
///   constraint pipeline needs (`pathComponents`, `swiftGenerics`,
///   `kind.identifier`); everything else is intentionally absent so
///   the decoder doesn't pay for fields we discard. See SwiftDocC's
///   `SymbolKit` for the full reference shape.
/// - `AppleConstraintsKit.URIMapper`: pure-function transform from a
///   symbol's `pathComponents` + framework module name to the
///   cupertino-internal `apple-docs://<framework>/<path>` URI shape.
///   Pure / stateless; passes the
///   `gof-di-rules.md` "Pure free functions" allowance.
/// - `AppleConstraintsKit.Extractor`: streaming-style parse of one
///   symbol-graph JSON file into a sequence of
///   `Search.StaticConstraintEntry` values. Filters to symbols with
///   non-empty `swiftGenerics.constraints`.
/// - `AppleConstraintsKit.Table`: in-memory + JSON-on-disk
///   representation of the filtered table. Conforms to
///   `Search.StaticConstraintsLookup` so a binary can construct one
///   and inject it into `Search.IndexBuilder`.
///
/// **Import contract** (per `gof-di-rules.md` rule 8. producer
/// foundation-only):
/// - Foundation
/// - SearchModels (for `Search.StaticConstraintsLookup` conformance)
///
/// **Standalone-portable.** Lifts out of the monorepo with only
/// Foundation + SearchModels (which itself is foundation-only). No
/// transitive coupling to producer targets.
///
/// **No Singletons** (rule 1). Tables are values; the binary
/// composition root constructs once and threads down. The CLI's
/// `CLIImpl.Composition` is where the `AppleConstraintsKit.Table` is
/// loaded from disk and passed to `Search.IndexBuilder.init`.
public enum AppleConstraintsKit {}
