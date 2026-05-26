import Foundation

// MARK: - Distribution.ArtifactDownloader — value types + Observer protocol

extension Distribution {
    /// File downloader namespace. The concrete `download(...)` static
    /// function lives in the `Distribution` producer target as an
    /// extension on this enum. The value types and Observer protocol
    /// stay here so any conformer can implement without depending on
    /// the producer target.
    public enum ArtifactDownloader {
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

        /// GoF Observer (1994 p. 293) for `ArtifactDownloader.download`
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
