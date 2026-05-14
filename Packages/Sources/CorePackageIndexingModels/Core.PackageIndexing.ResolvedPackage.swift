import CoreProtocols
import Foundation
import SharedConstants
// MARK: - Core.PackageIndexing.ResolvedPackage

extension Core.PackageIndexing {
    /// One entry in the resolved closure. Seeds list themselves as their own parent;
    /// transitively-discovered packages list every seed whose dependency graph reached
    /// them (can be multiple, which is how the store records a shared dependency).
    ///
    /// Lifted from `CorePackageIndexing` into this `CorePackageIndexingModels`
    /// value-types target so consumers (`Search.PackageIndex`,
    /// `Search.PackageIndexer`, `TUI.PackageActions`, `CLIImpl.Command.Fetch`) can
    /// reference it without pulling in the full indexer + extractor + annotator
    /// surface. The companion `ResolvedPackagesStore` writer / loader stays in
    /// `CorePackageIndexing` because it touches the filesystem.
    public struct ResolvedPackage: Codable, Sendable, Hashable {
        public let owner: String
        public let repo: String
        public let url: String
        public let priority: Shared.Models.PackagePriority
        public let parents: [String]

        public init(
            owner: String,
            repo: String,
            url: String,
            priority: Shared.Models.PackagePriority,
            parents: [String]
        ) {
            self.owner = owner
            self.repo = repo
            self.url = url
            self.priority = priority
            self.parents = parents
        }
    }
}
