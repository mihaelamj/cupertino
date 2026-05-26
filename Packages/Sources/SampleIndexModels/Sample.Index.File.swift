import Foundation
import SharedConstants

// MARK: - Sample File Model

extension Sample.Index {
    /// Represents an indexed source file within a sample project
    public struct File: Sendable, Codable, Equatable {
        /// Project ID this file belongs to
        public let projectId: String

        /// Relative path within the project (e.g., "Sources/Views/ContentView.swift")
        public let path: String

        /// Filename only (e.g., "ContentView.swift")
        public let filename: String

        /// Folder path (e.g., "Sources/Views")
        public let folder: String

        /// File extension (e.g., "swift")
        public let fileExtension: String

        /// Full file content
        public let content: String

        /// File size in bytes
        public let size: Int

        /// JSON-encoded array of `{line, raw, platforms[]}` capturing
        /// every `@available(...)` attribute occurrence in this file.
        /// Populated by `SampleIndexBuilder` during indexing (#228 phase 2).
        /// nil when the file had no attributes (distinct from "annotation
        /// didn't run" — annotation always runs for `.swift` files now).
        public let availableAttrsJSON: String?

        public init(
            projectId: String,
            path: String,
            content: String,
            availableAttrsJSON: String? = nil
        ) {
            self.projectId = projectId
            self.path = path
            self.content = content
            size = content.utf8.count
            self.availableAttrsJSON = availableAttrsJSON

            // Extract filename and folder from path
            let url = URL(fileURLWithPath: path)
            filename = url.lastPathComponent
            fileExtension = url.pathExtension.lowercased()

            // Get folder by removing filename
            let components = path.components(separatedBy: "/")
            if components.count > 1 {
                folder = components.dropLast().joined(separator: "/")
            } else {
                folder = ""
            }
        }
    }

    /// File types to index (text-based files only)
    public static let indexableExtensions: Set<String> = [
        // Swift
        "swift",
        // Objective-C
        "h", "m", "mm",
        // C/C++
        "c", "cpp", "hpp",
        // Metal
        "metal",
        // Config/Data
        "plist", "json", "strings", "entitlements", "xcconfig",
        // Documentation
        "md", "txt", "rtf",
        // Other
        "mlmodel", "storyboard", "xib",
    ]

    /// Check if a file should be indexed based on extension
    public static func shouldIndex(path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return indexableExtensions.contains(ext)
    }
}
