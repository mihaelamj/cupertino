// This file makes CupertinoResources a valid SPM target.
// The real resources are the JSON files in this directory.

import Foundation

/// Public accessor for CupertinoResources bundle.
/// Provides access to embedded resource files like sample-code-catalog.json.
public enum CupertinoResources {
    /// Public accessor for the resources bundle
    public static let bundle = Bundle.module
}
