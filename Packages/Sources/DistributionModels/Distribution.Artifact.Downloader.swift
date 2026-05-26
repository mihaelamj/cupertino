import Foundation

// MARK: - Distribution.Artifact.Downloader — value types + Observer protocol

/// Sub-namespace grouping for artifact-related types (downloader,
/// extractor, ...). Post-#1042 type-name deepening: previously these
/// lived at `Distribution.ArtifactDownloader` / `Distribution.ArtifactExtractor`;
/// the new path is `Distribution.Artifact.Downloader` /
/// `Distribution.Artifact.Extractor`. A `typealias ArtifactDownloader =
/// Artifact.Downloader` (declared at the bottom) keeps pre-#1042
/// call-sites compiling until they migrate.
extension Distribution {
    public enum Artifact {}
}

extension Distribution.Artifact {
    /// File downloader namespace. The concrete `download(...)` static
    /// function lives in the `Distribution` producer target as an
    /// extension on this enum. The value types and Observer protocol
    /// stay here so any conformer can implement without depending on
    /// the producer target.
    public enum Downloader {
        /// Snapshot of in-flight download state passed to a
        /// `ProgressObserving` conformer.
        public struct Progress: Sendable {
            public let bytesWritten: Int64
            /// `nil` when the server didn't advertise Content-Length;
            /// caller can fall back to its own approximate size.
            public let totalBytes: Int64?

            public init(bytesWritten: Int64, totalBytes: Int64?) {
                self.bytesWritten = bytesWritten
                self.totalBytes = totalBytes
            }
        }

        /// GoF Observer (1994 p. 293) for `Downloader.download`
        /// progress. Replaces the previous inline
        /// `onProgress: (@Sendable (Progress) -> Void)?` closure
        /// parameter. Per the standing cupertino rule "no closures,
        /// they ate magic."
        public protocol ProgressObserving: Sendable {
            /// Called per `URLSessionDownloadDelegate.didWriteData`
            /// event (~10 Hz on a typical network). Implementations
            /// should be non-blocking; the delegate queue serialises
            /// calls but doesn't wait beyond the protocol method's
            /// own return.
            func observe(progress: Progress)
        }
    }
}

/// Back-compat alias for pre-#1042 consumers. Existing references
/// to `Distribution.ArtifactDownloader.Progress` /
/// `Distribution.ArtifactDownloader.ProgressObserving` keep compiling;
/// new code uses `Distribution.Artifact.Downloader.*` directly.
extension Distribution {
    public typealias ArtifactDownloader = Artifact.Downloader
}
