import Foundation
@_exported import DistributionModels

// MARK: - Distribution module — concrete `cupertino setup` orchestrator
//
// The `Distribution` namespace anchor lives in the foundation-only
// `DistributionModels` seam target (Pattern A, matching `Search` /
// `SearchModels` and `Indexer` / `IndexerModels`). This producer
// target extends the seam-defined enums with concrete behaviour:
//
// - `Distribution.SetupService.run(...)` — orchestrator static func
// - `Distribution.ArtifactDownloader.download(...)` — URLSession download
// - `Distribution.ArtifactExtractor.extract(...)` — ZIP extraction
// - `Distribution.InstalledVersion.read / .write / .classify` — stamp helpers
//
// `@_exported import DistributionModels` makes the seam-target value
// types and Observer protocols reachable through `import Distribution`
// so existing callers that only need `import Distribution` keep
// compiling. The CLI binary's composition root explicitly imports
// both to make the seam dependency visible at the call site.
