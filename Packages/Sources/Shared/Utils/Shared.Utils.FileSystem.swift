import Foundation

// FileManager URL-based APIs fail with POSIX ENOTDIR when the target is a
// symlink-to-directory. Resolving symlinks before the call avoids this; see
// GitHub issue #786 for the full audit of affected call sites.
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
