import Foundation
import SharedConstants

// MARK: - GitHub Fetcher

extension RemoteSync {
    /// Actor for fetching documentation from GitHub.
    /// Uses raw.githubusercontent.com for content (no rate limits) and GitHub API for directory listings.
    public actor GitHubFetcher {
        /// Repository in format "owner/repo"
        public let repository: String

        /// Branch name
        public let branch: String

        /// URL session for HTTP requests
        private let session: URLSession

        /// Cached tree structure (fetched once, used for all lookups)
        private var cachedTree: [String: [GitHubTreeItem]]?

        // MARK: - Initialization

        /// GitHub token for authenticated requests (optional, increases rate limit)
        private let token: String?

        public init(
            repository: String = RemoteSync.defaultRepository,
            branch: String = RemoteSync.defaultBranch,
            session: URLSession = .shared,
            token: String? = ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.githubToken]
        ) {
            self.repository = repository
            self.branch = branch
            self.session = session
            self.token = token
        }

        // MARK: - Tree API (Single call for entire repo)

        /// Fetch and cache the entire repository tree
        private func ensureTreeLoaded() async throws {
            if cachedTree != nil { return }

            let url = try URL(knownGood: "\(RemoteSync.gitHubAPIBaseURL)/repos/\(repository)/git/trees/\(branch)?recursive=1")
            var request = URLRequest(url: url)

            // Add auth header if token available
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await session.data(for: request)

            try validateResponse(response, for: url)

            let treeResponse = try JSONDecoder().decode(GitHubTreeResponse.self, from: data)

            // Group items by parent directory
            var tree: [String: [GitHubTreeItem]] = [:]
            for item in treeResponse.tree {
                let parentPath = (item.path as NSString).deletingLastPathComponent
                tree[parentPath, default: []].append(item)
            }

            cachedTree = tree
        }

        // MARK: - Directory Listing

        /// Fetch list of directories in a path (e.g., frameworks in /docs)
        public func fetchDirectoryList(path: String) async throws -> [String] {
            try await ensureTreeLoaded()

            let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let items = cachedTree?[cleanPath] ?? []

            return items
                .filter { $0.type == "tree" }
                .map { ($0.path as NSString).lastPathComponent }
                .sorted()
        }

        /// Fetch list of files in a directory
        public func fetchFileList(path: String) async throws -> [FileInfo] {
            try await ensureTreeLoaded()

            let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let items = cachedTree?[cleanPath] ?? []

            return items
                .filter { $0.type == "blob" }
                .map {
                    FileInfo(
                        name: ($0.path as NSString).lastPathComponent,
                        path: $0.path,
                        size: $0.size ?? 0
                    )
                }
                .sorted { $0.name < $1.name }
        }

        // MARK: - File Content (Raw GitHub)

        /// Fetch raw file content
        public func fetchFileContent(path: String) async throws -> Data {
            let url = try buildRawURL(path: path)
            let (data, response) = try await session.data(from: url)

            try validateResponse(response, for: url)

            return data
        }

        /// Fetch and decode JSON file
        public func fetchJSON<T: Decodable>(path: String, as type: T.Type) async throws -> T {
            let data = try await fetchFileContent(path: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        }

        /// Fetch file as string
        public func fetchString(path: String) async throws -> String {
            let data = try await fetchFileContent(path: path)
            guard let string = String(data: data, encoding: .utf8) else {
                throw Error.invalidEncoding(path: path)
            }
            return string
        }

        // MARK: - URL Building

        private func buildRawURL(path: String) throws -> URL {
            let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let urlString = "\(RemoteSync.rawGitHubBaseURL)/\(repository)/\(branch)/\(cleanPath)"
            return try URL(knownGood: urlString)
        }

        // MARK: - Response Validation

        private func validateResponse(_ response: URLResponse, for url: URL) throws {
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.invalidResponse(url: url)
            }

            switch httpResponse.statusCode {
            case 200...299:
                return
            case 403:
                throw Error.rateLimited
            case 404:
                throw Error.notFound(url: url)
            default:
                throw Error.httpError(statusCode: httpResponse.statusCode, url: url)
            }
        }
    }
}

// MARK: - GitHub Tree API Response (internal helpers, scoped to this file)

/// GitHub Git Tree API response
private struct GitHubTreeResponse: Decodable {
    let sha: String
    let tree: [GitHubTreeItem]
    let truncated: Bool
}

/// Item in Git tree
private struct GitHubTreeItem: Decodable {
    let path: String
    let type: String // "blob" for files, "tree" for directories
    let size: Int?
}
