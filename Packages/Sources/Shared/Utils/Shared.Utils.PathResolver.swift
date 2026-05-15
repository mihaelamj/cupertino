import Foundation

// MARK: - Path Resolver

/// Pure-function path helpers. Post-#535 the previous Service-Locator-shaped
/// convenience accessors (`searchDatabase()`, `docsDirectory()`,
/// `evolutionDirectory()`, `higDirectory()`, `sampleCodeDirectory()`) are
/// gone — they routed through `Shared.Constants.defaultX` and hid a
/// `BinaryConfig.shared` read at the callsite. Callers now thread a
/// `Shared.Paths` value through their composition root and pick the URL
/// they want directly.
///
/// What remains here is the stateless, path-shape-only surface:
/// `directory(_:default:)` to apply an explicit fallback, `expand(_:)`
/// for tilde-expansion, and the `exists` / `isDirectory` filesystem
/// probes.
extension Shared.Utils {
    public enum PathResolver {
        // MARK: - Directory Resolution

        /// Resolve a directory path: either the explicit custom path
        /// (tilde-expanded) or the provided default URL.
        /// - Parameters:
        ///   - customPath: Optional custom path (supports ~ expansion)
        ///   - defaultPath: Default path if custom is not provided
        /// - Returns: Resolved URL to the directory
        public static func directory(_ customPath: String? = nil, default defaultPath: URL) -> URL {
            if let customPath {
                return URL(fileURLWithPath: customPath).expandingTildeInPath
            }
            return defaultPath
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
}
