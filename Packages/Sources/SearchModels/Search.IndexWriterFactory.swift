import Foundation

// MARK: - Search.IndexWriterFactory

extension Search {
    /// Factory abstraction for opening a `Search.IndexWriter`-conforming
    /// actor from a file URL. GoF Factory Method (1994 p. 107),
    /// Swift-idiomatic expression.
    ///
    /// Mirrors `Search.DatabaseFactory` (the read-side counterpart). The
    /// composition root (the CLI binary) supplies a concrete factory
    /// that opens the production `Search.Index` actor against
    /// `search.db`; tests supply a stub. The rewire that switches
    /// `Search.IndexBuilder` + the 6 source-indexing strategies to
    /// consume `any Search.IndexWriterFactory` instead of constructing
    /// `Search.Index` directly lands separately under epic #893's child
    /// #897.
    ///
    /// GoF mapping:
    /// - "Product" = `any Search.IndexWriter`
    /// - "Creator" = `Search.IndexWriterFactory` protocol (this file)
    /// - "ConcreteCreator" = `LiveSearchIndexWriterFactory` in the CLI
    ///   composition root, added under #897 when the rewire lands.
    public protocol IndexWriterFactory: Sendable {
        /// Open (or create) a `Search.IndexWriter` at `url`. The
        /// concrete factory decides which actor to instantiate.
        func openWriter(at url: URL) async throws -> any Search.IndexWriter
    }
}
