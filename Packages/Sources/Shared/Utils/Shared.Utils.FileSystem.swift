import Foundation

extension Shared.Utils {
    /// #786 / symlink-safe wrappers around the `FileManager` URL-variant
    /// directory-listing APIs.
    ///
    /// `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`
    /// and `FileManager.enumerator(at:includingPropertiesForKeys:options:)`,
    /// the URL-taking variants of these APIs, do NOT follow a directory
    /// symlink at the leaf URL. They operate on the symlink inode itself;
    /// the kernel returns `ENOTDIR` (POSIX errno 20); Foundation wraps it
    /// as `NSCocoaErrorDomain` code 256 (`NSFileReadUnknownError`) with the
    /// bare `localizedDescription` `"The file \"X\" couldn't be opened."`
    /// (no `because…` suffix, because `ENOTDIR` does not map to a more
    /// specific Cocoa code).
    ///
    /// The String-variant siblings (`contentsOfDirectory(atPath:)`) and
    /// `FileManager.fileExists(atPath:)` both follow symlinks correctly,
    /// which masks the URL-variant divergence at guard time.
    ///
    /// This class of bug was the root cause of #779. That fix landed in
    /// `Indexer.DocsService.optionalDir` (resolving symlinks before the
    /// URL reached any strategy). The same call shape exists at six other
    /// places in the codebase, all of which would fail identically if any
    /// of them is ever passed a leaf directory-symlink. These wrappers
    /// pre-resolve via `URL.resolvingSymlinksInPath()` and delegate to
    /// the raw API, so the URL-variant return type is preserved (`[URL]`,
    /// `FileManager.DirectoryEnumerator`) and the caller writes idiomatic
    /// Swift the same way as before.
    ///
    /// `URL.resolvingSymlinksInPath()` is a no-op on non-symlink URLs:
    /// the wrappers are safe for every existing caller regardless of
    /// whether the input ever points at a symlink. One extra syscall per
    /// call (sub-microsecond); below noise.
    ///
    /// New code reading directories from URLs should reach for these
    /// wrappers instead of the raw `FileManager` URL-variant APIs.
    public enum FileSystem {
        /// Symlink-safe wrapper around
        /// `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`.
        ///
        /// Pre-resolves the URL via `URL.resolvingSymlinksInPath()` so a
        /// leaf directory-symlink at `url` is dereferenced before the
        /// underlying `getattrlistbulk` syscall sees it.
        ///
        /// - Parameters:
        ///   - url: Directory to enumerate. May be a real directory or a
        ///     symlink to one; both work.
        ///   - keys: Optional resource keys to prefetch for each returned
        ///     URL (forwarded to the raw API unchanged).
        ///   - options: Enumeration options (forwarded unchanged).
        /// - Returns: The entries of the (possibly symlink-resolved)
        ///   directory.
        /// - Throws: Any error the underlying API throws, except the
        ///   specific `ENOTDIR`-from-leaf-symlink case that this wrapper
        ///   defuses.
        public static func contentsOfDirectory(
            at url: URL,
            includingPropertiesForKeys keys: [URLResourceKey]?,
            options: FileManager.DirectoryEnumerationOptions = []
        ) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(
                at: url.resolvingSymlinksInPath(),
                includingPropertiesForKeys: keys,
                options: options
            )
        }

        /// Symlink-safe wrapper around
        /// `FileManager.enumerator(at:includingPropertiesForKeys:options:)`.
        ///
        /// Pre-resolves the URL via `URL.resolvingSymlinksInPath()` so a
        /// leaf directory-symlink at `url` is dereferenced before
        /// enumeration starts.
        ///
        /// - Parameters:
        ///   - url: Directory root to walk. May be a real directory or a
        ///     symlink to one; both work.
        ///   - keys: Optional resource keys to prefetch (forwarded
        ///     unchanged).
        ///   - options: Enumeration options (forwarded unchanged).
        /// - Returns: A directory enumerator, or `nil` if the underlying
        ///   API returns `nil`.
        public static func enumerator(
            at url: URL,
            includingPropertiesForKeys keys: [URLResourceKey]?,
            options: FileManager.DirectoryEnumerationOptions = []
        ) -> FileManager.DirectoryEnumerator? { // matches raw FileManager URL-variant default
            FileManager.default.enumerator(
                at: url.resolvingSymlinksInPath(),
                includingPropertiesForKeys: keys,
                options: options
            )
        }
    }
}
