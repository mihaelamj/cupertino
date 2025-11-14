import Foundation

/// Helper to access Components package bundle resources
public enum ComponentsBundle {
    /// The bundle containing Components package resources
    private static let bundle = Bundle.module

    /// Get the path to components.json
    /// Prioritizes source location (for Xcode editing), falls back to bundle resources (for deployed apps)
    public static var componentsJsonPath: String? {
        // Try source location first for development (allows editing in Xcode)
        var codePath = #file.components(separatedBy: "/")
        codePath.removeLast() // Remove "ComponentsBundle.swift"
        let sourcePath = codePath.joined(separator: "/") + "/components.json"

        print("📦 ComponentsBundle checking source path: \(sourcePath)")
        print("📦 Source file exists: \(FileManager.default.fileExists(atPath: sourcePath))")
        print("📦 Source file isReadable: \(FileManager.default.isReadableFile(atPath: sourcePath))")

        if FileManager.default.fileExists(atPath: sourcePath) {
            print("📦 ✅ Loading components.json from source: \(sourcePath)")
            return sourcePath
        }

        // Fall back to bundle resource for deployed apps
        if let bundlePath = bundle.path(forResource: "components", ofType: "json") {
            print("📦 ⚠️ Loading components.json from bundle: \(bundlePath)")
            print("📦 (Hot reload won't work from bundle - need source path)")
            return bundlePath
        }

        print("⚠️ components.json not found in source or bundle")
        return nil
    }
}
