import ArgumentParser
import Foundation
import SharedConstants

// MARK: - Supporting Types

// Post-#1031 (Phase 1I.c.2 of epic #1007): `Cupertino.FetchType`
// enum dissolved. The fetch CLI now dispatches on canonical
// source-id strings (matching `Search.SourceProvider.definition.id`).
// All per-type metadata (displayName / defaultURL /
// defaultAllowedPrefixes / defaultOutputDir / webCrawlTypes /
// directFetchTypes / allTypes) moved to the per-source target's
// `*.FetchInfo.swift` files. The CLI's `cupertino fetch --source <id>`
// command derives the lookups from `CLIImpl.makeProductionSourceRegistry()`.
//
// File kept as a historical anchor; no live exports remain.
