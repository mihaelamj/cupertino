import Foundation

// MARK: - Search.DocsReadStrategy

extension Search {
    /// Shared read strategy for the 6 docs-tier sources (apple-docs,
    /// hig, apple-archive, swift-evolution, swift-org, swift-book).
    /// Each source's `makeReadStrategy()` returns an instance with
    /// its own source-id baked in; the strategy resolves the
    /// per-source DB URL from `env.dbURLs[sourceID]` (falling
    /// back to `env.fallbackSearchDB` for callers that haven't
    /// migrated to the per-source map), then asks `env.docsLookup`
    /// for the content.
    ///
    /// Returns nil when:
    /// - The identifier does NOT carry a `<sourceID>://` scheme and
    ///   does NOT match the bare slug shape that docs URIs accept;
    /// - Or the docs lookup returns nil (404 against this DB).
    ///
    /// Returning nil drives the auto-source fallback in
    /// `Services.ReadService` (try samples → packages → docs).
    public struct DocsReadStrategy: SourceReadStrategy {
        public let sourceID: String

        public init(sourceID: String) {
            self.sourceID = sourceID
        }

        public func read(env: ReadEnvironment) async throws -> ReadResult? {
            let dbURL = env.dbURLs[sourceID] ?? env.fallbackSearchDB
            guard let content = try await env.docsLookup.read(
                uri: env.identifier,
                format: env.format,
                dbURL: dbURL
            ) else {
                // Not found in this DB. Auto-source flow continues to
                // the next strategy; an explicit-source read surfaces
                // a not-found error to the caller via `Services.ReadService`.
                return nil
            }
            return ReadResult(content: content, resolvedSourceID: sourceID)
        }
    }
}
