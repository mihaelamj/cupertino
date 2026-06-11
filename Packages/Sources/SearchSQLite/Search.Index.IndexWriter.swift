import Foundation
import SearchModels

// MARK: - Search.Index <-> Search.IndexWriter witness

// `Search.Index` (the concrete actor in this SearchSQLite target)
// already implements every method on `Search.IndexWriter` (defined in
// `SearchModels`): the protocol is the exact write surface that
// `Search.IndexBuilder`, the 6 source-indexing strategies (all in the
// sibling Search orchestration target), and the indexer-side CLI
// runner call. This one-line witness lets those consumers receive
// `any Search.IndexWriter` while the concrete actor stays unchanged.
//
// Mirrors the read-side witness in `Search.Index.Database.swift`
// (`extension Search.Index: Search.Database {}`). Added by epic #893's
// child #896; both witnesses moved into this target by #898 sub-PR E.
extension Search.Indexer: Search.IndexWriter {}
