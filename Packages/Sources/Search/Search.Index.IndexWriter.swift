import Foundation
import SearchModels

// MARK: - Search.Index <-> Search.IndexWriter witness

// `Search.Index` (the concrete actor in this Search SPM target) already
// implements every method on `Search.IndexWriter` (defined in
// `SearchModels`): the protocol is the exact write surface that
// `Search.IndexBuilder`, the 7 source-indexing strategies, and the
// indexer-side CLI runner call. This one-line witness lets those
// consumers receive `any Search.IndexWriter` while the concrete actor
// stays unchanged.
//
// Mirrors the read-side witness in `Search.Index.Database.swift`
// (`extension Search.Index: Search.Database {}`). Added by epic #893's
// child #896. The rewire of `IndexBuilder` + strategies to actually
// take `any Search.IndexWriter` via init lands separately under #897.
extension Search.Index: Search.IndexWriter {}
