// This file makes CupertinoResources a valid SPM target.
// The real resources are the JSON files in this directory.

import Foundation

/// Public accessor for CupertinoResources bundle.
/// Provides access to embedded resource files like sample-code-catalog.json.
public enum CupertinoResources {
    /// Public accessor for the resources bundle.
    /// Uses SPM's Bundle.module first, then falls back to resolving symlinks
    /// (needed for Homebrew installations where the binary is symlinked).
    public static let bundle: Bundle = {
        // SPM-generated Bundle.module checks Bundle.main.bundleURL, but that doesn't
        // resolve symlinks. For Homebrew installs, the binary is symlinked from
        // /opt/homebrew/bin/ → Cellar, so Bundle.main.bundleURL points to the wrong dir.
        // Try the resolved-symlink path first, then fall back to Bundle.module.
        if let execURL = Bundle.main.executableURL {
            let resolved = execURL.resolvingSymlinksInPath().deletingLastPathComponent()
            let resolvedBundle = resolved.appendingPathComponent("Cupertino_Resources.bundle")
            if let bundle = Bundle(url: resolvedBundle) {
                return bundle
            }
        }
        return Bundle.module
    }()
}
