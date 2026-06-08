import Foundation

// MARK: - Shared.Utils Home Directory

extension Shared.Utils {
    /// Platform-portable home directory.
    ///
    /// `FileManager.homeDirectoryForCurrentUser` is macOS-only. App-platform
    /// builds use `NSHomeDirectory()` so read-only embedded targets can compile
    /// even though they normally receive explicit database locations.
    public static var homeDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory())
        #endif
    }
}
