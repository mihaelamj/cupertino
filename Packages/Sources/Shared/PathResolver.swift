import Foundation

// MARK: - Path Resolver

/// Centralized path resolution for database files and directories.
/// Consolidates path resolution logic used across CLI commands and tool providers.
public enum PathResolver {
    // MARK: - Search Database

    /// Resolve the search database path.
    /// - Parameter customPath: Optional custom path (supports ~ expansion)
    /// - Returns: Resolved URL to the search database
    public static func searchDatabase(_ customPath: String? = nil) -> URL {
        if let customPath {
            return URL(fileURLWithPath: customPath).expandingTildeInPath
        }
        return Shared.Constants.defaultSearchDatabase
    }

    // MARK: - Directory Resolution

    /// Resolve a documentation directory path.
    /// - Parameter customPath: Optional custom path (supports ~ expansion)
    /// - Parameter defaultPath: Default path if custom is not provided
    /// - Returns: Resolved URL to the directory
    public static func directory(_ customPath: String? = nil, default defaultPath: URL) -> URL {
        if let customPath {
            return URL(fileURLWithPath: customPath).expandingTildeInPath
        }
        return defaultPath
    }

    /// Resolve the docs directory.
    public static func docsDirectory(_ customPath: String? = nil) -> URL {
        directory(customPath, default: Shared.Constants.defaultDocsDirectory)
    }

    /// Resolve the Swift Evolution directory.
    public static func evolutionDirectory(_ customPath: String? = nil) -> URL {
        directory(customPath, default: Shared.Constants.defaultSwiftEvolutionDirectory)
    }

    /// Resolve the HIG directory.
    public static func higDirectory(_ customPath: String? = nil) -> URL {
        directory(customPath, default: Shared.Constants.defaultHIGDirectory)
    }

    /// Resolve the sample code directory.
    public static func sampleCodeDirectory(_ customPath: String? = nil) -> URL {
        directory(customPath, default: Shared.Constants.defaultSampleCodeDirectory)
    }

    // MARK: - Path Expansion

    /// Expand a path string with tilde support.
    /// - Parameter path: Path string (may include ~)
    /// - Returns: Expanded URL
    public static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: path).expandingTildeInPath
    }

    // MARK: - Validation

    /// Check if a path exists.
    /// - Parameter url: URL to check
    /// - Returns: true if the path exists
    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Check if a path exists and is a directory.
    /// - Parameter url: URL to check
    /// - Returns: true if the path exists and is a directory
    public static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
