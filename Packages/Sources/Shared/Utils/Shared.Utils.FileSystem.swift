import Foundation

extension Shared.Utils {
    /// Symlink-safe wrappers around FileManager directory-enumeration APIs.
    ///
    /// URL-based FileManager methods (contentsOfDirectory(at:) and
    /// enumerator(at:)) fail with POSIX ENOTDIR when the final path component
    /// is a symlink to a directory. Calling resolvingSymlinksInPath() before
    /// forwarding to FileManager resolves the leaf symlink so the kernel sees a
    /// real directory inode. This is a no-op on canonical paths.
    public enum FileSystem {
        public static func contentsOfDirectory(
            at url: URL,
            includingPropertiesForKeys keys: [URLResourceKey]?,
            options: FileManager.DirectoryEnumerationOptions = []
        ) throws -> [URL] {
            let resolved = url.resolvingSymlinksInPath()
            return try FileManager.default.contentsOfDirectory(
                at: resolved,
                includingPropertiesForKeys: keys,
                options: options
            )
        }

        public static func enumerator(
            at url: URL,
            includingPropertiesForKeys keys: [URLResourceKey]?,
            options: FileManager.DirectoryEnumerationOptions = [],
            errorHandler: ((URL, Error) -> Bool)? = nil
        ) -> FileManager.DirectoryEnumerator? {
            let resolved = url.resolvingSymlinksInPath()
            return FileManager.default.enumerator(
                at: resolved,
                includingPropertiesForKeys: keys,
                options: options,
                errorHandler: errorHandler
            )
        }
    }
}
