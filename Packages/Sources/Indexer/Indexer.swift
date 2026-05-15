import Foundation
@_exported import IndexerModels

// MARK: - Indexer module — concrete orchestrators
//
// The `Indexer` namespace anchor lives in the foundation-only
// `IndexerModels` seam target (Pattern A, matching how `Search` lives
// in `SearchModels` and `Sample.*` lives in `SampleIndexModels`). This
// producer target extends the seam-defined enums with concrete
// orchestrator behaviour:
//
// - `Indexer.DocsService.run(...)` static func (in
//   `Indexer.DocsService.swift`)
// - `Indexer.PackagesService.run(...)` static func
// - `Indexer.SamplesService.run(...)` static func
// - `Indexer.Preflight.*` helpers (`Indexer.Preflight.swift`)
//
// `@_exported import IndexerModels` makes the seam-target value types
// and Observer protocols reachable through `import Indexer` so existing
// callers that only need `import Indexer` keep compiling. CLI's
// composition root explicitly imports both to make the seam dependency
// visible at the call site.
