import ASTIndexer
import CoreProtocols
import Foundation

// MARK: - Core.PackageIndexing.AnnotationResult

/// The output of a single `PackageAvailabilityAnnotator.annotate(...)`
/// call. Lifted to a top-level value type under `Core.PackageIndexing.*`
/// so consumers (`Search.PackageIndexer`) can hold it without pulling in
/// the full `CorePackageIndexing` target.
///
/// Previously nested as
/// `Core.PackageIndexing.PackageAvailabilityAnnotator.AnnotationResult`.
/// Callers that wrote that fully-qualified name now write
/// `Core.PackageIndexing.AnnotationResult`. Same renaming pattern as
/// `PackageArchiveExtractor.Result → PackageExtractionResult` and
/// `Sample.Index.Database.FileSearchResult → Sample.Index.FileSearchResult`.
extension Core.PackageIndexing {
    public struct AnnotationResult: Codable, Sendable, Equatable {
        public let version: String
        public let annotatedAt: Date
        public let deploymentTargets: [String: String]
        public let fileAvailability: [FileAvailability]
        public let stats: Stats

        public init(
            version: String,
            annotatedAt: Date,
            deploymentTargets: [String: String],
            fileAvailability: [FileAvailability],
            stats: Stats
        ) {
            self.version = version
            self.annotatedAt = annotatedAt
            self.deploymentTargets = deploymentTargets
            self.fileAvailability = fileAvailability
            self.stats = stats
        }

        /// Run-summary numbers attached to every annotation pass.
        public struct Stats: Codable, Sendable, Equatable {
            public let filesScanned: Int
            public let filesWithAvailability: Int
            public let totalAttributes: Int

            public init(
                filesScanned: Int,
                filesWithAvailability: Int,
                totalAttributes: Int
            ) {
                self.filesScanned = filesScanned
                self.filesWithAvailability = filesWithAvailability
                self.totalAttributes = totalAttributes
            }
        }
    }

    /// Per-source-file availability annotation. Lifted alongside
    /// `AnnotationResult` so the `[FileAvailability]` field on the result
    /// resolves cleanly from this Models target.
    public struct FileAvailability: Codable, Sendable, Equatable {
        public let relpath: String
        public let attributes: [Attribute]

        public init(relpath: String, attributes: [Attribute]) {
            self.relpath = relpath
            self.attributes = attributes
        }
    }

    /// Re-exported under the original public name for source / binary
    /// stability. The underlying value type comes from `ASTIndexer.AvailabilityParsers`
    /// (the parser helpers that emit one of these per matched `@available(...)`
    /// occurrence). The typealias sits under `Core.PackageIndexing.*` so
    /// `FileAvailability.attributes: [Core.PackageIndexing.Attribute]` reads
    /// naturally at the call site.
    public typealias Attribute = ASTIndexer.AvailabilityParsers.Attribute
}
