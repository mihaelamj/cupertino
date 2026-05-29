import Foundation

// MARK: - Search.URIResource + ResourceListMode

extension Search {
    /// One entry in the MCP `resources/list` page. Mirrors
    /// `MCP.Core.Protocols.Resource` but stays in the foundation tier so
    /// per-source enumeration code + the MCP layer share one value type
    /// without MCPSupport importing MCP.Core. The composition-root
    /// lookup concrete builds these from the per-source DBs; the
    /// dispatcher in `MCP.Support.DocsResourceProvider` maps them to
    /// `Protocols.Resource` at the boundary.
    public struct URIResource: Sendable, Equatable {
        public let uri: String
        public let name: String
        public let description: String

        public init(uri: String, name: String, description: String) {
            self.uri = uri
            self.name = name
            self.description = description
        }
    }

    /// How a source's per-source SQLite DB enumerates its slice of the
    /// MCP `resources/list` page. Principle 7 (`docs/PRINCIPLES.md`):
    /// the list is built purely from the DB, never the filesystem.
    ///
    /// Replaces the pre-2026-05-28 filesystem-probing
    /// `Search.URIResourceStrategy` + `Search.URIResourceEnvironment`
    /// (which read `sourceDirectory` / `CrawlMetadata` off disk). Post
    /// per-source-DB-split (#1036) the legacy monolithic `search.db`
    /// isn't built, so the file-based provider always returned empty;
    /// the resources path now reads the same per-source DBs the MCP
    /// search/read tools use.
    ///
    /// `RawRepresentable` struct (same shape as `Search.SearchRoute`)
    /// so adding a new mode is a `static let`, not a closed-enum edit.
    public struct ResourceListMode: RawRepresentable, Sendable, Equatable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Source does not expose MCP-resource URIs (samples, packages).
        /// The composition root skips it when building resources/list.
        public static let none = ResourceListMode(rawValue: "none")

        /// Enumerate every document row in the source's DB as a
        /// resource (small docs corpora: hig, swift-org, swift-book,
        /// swift-evolution, apple-archive).
        public static let allDocuments = ResourceListMode(rawValue: "all-documents")

        /// Enumerate one resource per framework root (large corpora:
        /// apple-docs, ~398 framework roots vs ~350k sub-pages). The
        /// framework-root URIs (`apple-docs://<framework>`) are
        /// themselves readable rows in the DB.
        public static let frameworkRoots = ResourceListMode(rawValue: "framework-roots")
    }
}

// MARK: - SourceProvider default

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
