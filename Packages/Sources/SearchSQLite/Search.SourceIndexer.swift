import Foundation

// MARK: - Vestigial after #1021

// As of #1021 (Phase 1G of epic #1007), all 7 per-source indexer
// concretes have been lifted out of this file into their own
// per-source SPM targets:
//
//   - Search.AppleDocsIndexer       lives in AppleDocsSource     (#1009)
//   - Search.HIGIndexer             lives in HIGSource           (#1011)
//   - Search.SampleCodeIndexer      lives in SampleCodeSource    (#1013)
//   - Search.AppleArchiveIndexer    lives in AppleArchiveSource  (#1016)
//   - Search.SwiftEvolutionIndexer  lives in SwiftEvolutionSource (#1018)
//   - Search.SwiftOrgIndexer        lives in SwiftOrgSource      (#1020)
//   - Search.SwiftBookIndexer       lives in SwiftBookSource     (#1021)
//
// #789: PackagesIndexer removed along with the search.db `packages`
// table. Package indexing lives in packages.db via the dedicated
// `Indexer.PackagesService` (`cupertino save --source packages`).
//
// #932: the static `Search.IndexerRegistry` enum was dissolved. The
// production indexer concretes are assembled inline at the
// composition root in `CLIImpl.Command.Save.Indexers.swift`. Naming a
// helper here would reintroduce a Service Locator surface
// (gof-di-rules.md Rule 1).
//
// File kept as a historical marker until phase 1I dissolves the
// older composition-root paths.
