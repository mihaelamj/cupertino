import CoreProtocols
import Foundation

// MARK: - Core.PackageIndexing.PackageExtractionResult

/// The output of a single `PackageArchiveExtractor.extract(...)` call.
///
/// Previously nested as `Core.PackageIndexing.PackageArchiveExtractor.Result`
/// inside the concrete actor. Lifted to a top-level value type under
/// `Core.PackageIndexing.*` so consumer targets (`Search.PackageIndex`,
/// `Search.PackageIndexer`, `CLIImpl.Command.Fetch`) can reference it without
/// pulling in the full extractor + indexer + annotator surface.
///
/// Callers that previously wrote
/// `Core.PackageIndexing.PackageArchiveExtractor.Result` now write
/// `Core.PackageIndexing.PackageExtractionResult`.
extension Core.PackageIndexing {
    public struct PackageExtractionResult: Sendable {
        public let branch: String
        public let files: [ExtractedFile]
        public let totalBytes: Int64
        public let tarballBytes: Int

        public init(
            branch: String,
            files: [ExtractedFile],
            totalBytes: Int64,
            tarballBytes: Int
        ) {
            self.branch = branch
            self.files = files
            self.totalBytes = totalBytes
            self.tarballBytes = tarballBytes
        }
    }
}
