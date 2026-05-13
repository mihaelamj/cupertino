import Foundation

// MARK: - GitHub Fetcher FileInfo

extension RemoteSync.GitHubFetcher {
    /// Information about a file in the repository
    public struct FileInfo: Sendable, Equatable {
        public let name: String
        public let path: String
        public let size: Int

        public init(name: String, path: String, size: Int) {
            self.name = name
            self.path = path
            self.size = size
        }
    }
}
