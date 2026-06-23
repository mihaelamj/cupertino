import Foundation

// MARK: - Search catalog browsing (samples, packages)

extension Search {
    /// One top-level entry of a **catalog** source (a sample project, or a package): the unit the
    /// unified `list` tool returns at level 1 for `samples`/`packages`. A catalog source is one
    /// whose corpus is a set of entries each holding a file tree, rather than a documentation graph;
    /// the engine enumerates the whole corpus (every project / every package, paged) instead of a
    /// capped search head.
    public struct CatalogEntry: Codable, Equatable, Sendable {
        /// The entry id used to address its children (`<scheme>://<id>`): a project id, or `owner/repo`.
        public let id: String
        /// Display title.
        public let title: String
        /// The number of files under the entry, for a count badge.
        public let fileCount: Int

        public init(id: String, title: String, fileCount: Int) {
            self.id = id
            self.title = title
            self.fileCount = fileCount
        }
    }

    /// One window of catalog entries with the total, so a caller can page the whole corpus.
    public struct CatalogEntryPage: Codable, Equatable, Sendable {
        public let entries: [CatalogEntry]
        public let offset: Int
        public let limit: Int
        public let total: Int

        public init(entries: [CatalogEntry], offset: Int, limit: Int, total: Int) {
            self.entries = entries
            self.offset = offset
            self.limit = limit
            self.total = total
        }
    }

    /// One node in a catalog entry's folder tree: a directory (expandable) or a leaf file (readable).
    public struct CatalogNode: Codable, Equatable, Sendable {
        /// The node's URI (`<scheme>://<entryID>/<path>`).
        public let uri: String
        /// The node's display name (its last path segment).
        public let name: String
        /// True for a directory (has children to expand); false for a leaf file.
        public let isDirectory: Bool

        public init(uri: String, name: String, isDirectory: Bool) {
            self.uri = uri
            self.name = name
            self.isDirectory = isDirectory
        }
    }
}
