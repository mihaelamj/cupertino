import Foundation

// MARK: - Indexer module namespace

/// `Indexer` is the write-side counterpart to `Search` and `SampleIndex`
/// (read side) and `Distribution` (download side). Lifted out of CLI
/// in #244 and decoupled into a foundation-only seam target during the
/// closures-to-Observer-protocols epic.
///
/// Each indexer takes raw on-disk corpus files and produces one of the
/// three local cupertino DBs:
/// - `Indexer.DocsService` → `search.db` (docs, evolution, swift.org,
///   archive, HIG)
/// - `Indexer.PackagesService` → `packages.db` (extracted package
///   archives at `~/.cupertino/packages/<owner>/<repo>/`)
/// - `Indexer.SamplesService` → `samples.db` (extracted sample-code
///   zips at `~/.cupertino/sample-code/`)
///
/// Plus `Indexer.Preflight` (defined in the `Indexer` producer target)
/// — pure on-disk inspection helpers used by both `cupertino save`
/// (before writing) and `cupertino doctor --save` (read-only health
/// check).
///
/// **Target split.** The value types (`Request`, `Outcome`, `Event`,
/// `ServiceError`, `Phase`) plus the GoF Observer protocols
/// (`*EventObserving`) live here in `IndexerModels` (foundation-only
/// seam). The concrete `static func run(...)` orchestrators live in
/// the `Indexer` producer target as extensions on the same enums.
/// Any test conformer of an `*EventObserving` protocol needs only
/// `import IndexerModels` — no producer-target dependency.
///
/// Services are UI-free: callers receive lifecycle events through a
/// typed Observer protocol conformer they construct at the composition
/// root and render whatever they want. CLI's `save` command renders
/// progress bars; an MCP tool could just collect counts.
public enum Indexer {}
