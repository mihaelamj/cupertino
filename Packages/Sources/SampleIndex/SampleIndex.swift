import Foundation

// MARK: - SampleIndex Namespace

/// SampleIndex provides indexing and search for Apple sample code projects.
/// Unlike the main Search database, SampleIndex uses a separate database
/// (`~/.cupertino/samples.db`) optimized for code-level search.
public enum SampleIndex {
    /// Default database path for source code search index
    public static var defaultDatabasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cupertino")
            .appendingPathComponent("samples.db")
    }

    /// Default sample code directory
    public static var defaultSampleCodeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cupertino")
            .appendingPathComponent("sample-code")
    }
}
