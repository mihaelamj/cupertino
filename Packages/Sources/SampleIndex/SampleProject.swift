import Foundation
import SharedConstants

// MARK: - Sample Project Model

extension Sample.Index {
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

        // MARK: Availability (#228 phase 2)

        /// Per-platform deployment targets parsed from `Package.swift`
        /// during the indexing pass. Same shape as the per-package
        /// version in `packages.db`. Empty when the sample shipped no
        /// `platforms: [...]` block (typical for Apple's Xcode-project
        /// samples).
        public let deploymentTargets: [String: String]

        /// Free-form tag describing where the availability data came
        /// from. Currently only `"sample-swift"` (parsed from
        /// `Package.swift` + `.swift` sources by `SampleIndexBuilder`).
        /// nil when no annotation was loaded.
        public let availabilitySource: String?

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
            indexedAt: Date = Date(),
            deploymentTargets: [String: String] = [:],
            availabilitySource: String? = nil
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
            self.deploymentTargets = deploymentTargets
            self.availabilitySource = availabilitySource
        }
    }
}
