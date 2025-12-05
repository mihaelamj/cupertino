// MARK: - RemoteSync Package

/// Remote documentation streaming from GitHub to SQLite.
/// Provides instant setup by streaming from pre-crawled cupertino-docs repo.
public enum RemoteSync {
    /// Package version
    public static let version = "1.0.0"

    /// Default GitHub repository for pre-crawled documentation
    public static let defaultRepository = "mihaelamj/cupertino-docs"

    /// Default branch
    public static let defaultBranch = "main"

    /// Raw GitHub content base URL
    public static let rawGitHubBaseURL = "https://raw.githubusercontent.com"

    /// GitHub API base URL
    public static let gitHubAPIBaseURL = "https://api.github.com"
}
