import Foundation

// `Search.URIResource` and `Search.ResourceListMode` are owned by
// CupertinoDataKit (the read contract) and re-exported via SharedConstants.
// This file keeps the producer-side default that maps a source to its
// resource-list mode — that logic depends on `Search.SourceProvider`
// (`isSearchTier`), which is cupertino-internal, not part of the contract.

extension Search.SourceProvider {
    /// Default resource-list mode. Search-tier docs sources enumerate
    /// every document; the 2 non-FTS sources (samples / packages)
    /// expose no MCP-resource URIs. apple-docs overrides to
    /// `.frameworkRoots` (its corpus is too large to list per-page).
    ///
    /// Adding a new docs source automatically joins resources/list via
    /// the default `.allDocuments`; a source with a different policy
    /// declares one `static let` mode + overrides this property — no
    /// edit to the MCP dispatcher or the composition root loop.
    public var resourceListMode: Search.ResourceListMode {
        isSearchTier ? .allDocuments : .none
    }
}
