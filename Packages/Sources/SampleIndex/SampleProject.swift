import Foundation

// MARK: - Sample Project Model

extension SampleIndex {
    /// Represents an indexed sample code project
    public struct Project: Sendable, Codable, Equatable {
        /// Unique identifier (slug from ZIP filename)
        public let id: String

        /// Project title
        public let title: String

        /// Project description
        public let description: String

        /// Frameworks used (lowercased for consistency)
        public let frameworks: [String]

        /// README content (markdown)
        public let readme: String?

        /// Web URL on Apple Developer
        public let webURL: String

        /// ZIP filename
        public let zipFilename: String

        /// Number of files in project
        public let fileCount: Int

        /// Total size of source files in bytes
        public let totalSize: Int

        /// When the project was indexed
        public let indexedAt: Date

        public init(
            id: String,
            title: String,
            description: String,
            frameworks: [String],
            readme: String?,
            webURL: String,
            zipFilename: String,
            fileCount: Int,
            totalSize: Int,
            indexedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.frameworks = frameworks.map { $0.lowercased() }
            self.readme = readme
            self.webURL = webURL
            self.zipFilename = zipFilename
            self.fileCount = fileCount
            self.totalSize = totalSize
            self.indexedAt = indexedAt
        }
    }
}
