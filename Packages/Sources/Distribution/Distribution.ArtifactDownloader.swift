import Foundation
import SharedConstants
import SharedCore

extension Distribution {
    /// Async file downloader with a progress callback. The callback fires
    /// per `URLSessionDownloadDelegate.didWriteData` event (~10 Hz on a
    /// typical network) so callers can render a progress bar without the
    /// service caring about UI. Renders nothing itself.
    public enum ArtifactDownloader {
        /// Snapshot of in-flight download state passed to `onProgress`.
        public struct Progress: Sendable {
            public let bytesWritten: Int64
            /// `nil` when the server didn't advertise Content-Length; caller
            /// can fall back to its own approximate size.
            public let totalBytes: Int64?
        }

        /// Download a file to `destination`, replacing any existing file
        /// at that path on success.
        ///
        /// - Parameters:
        ///   - urlString: source URL.
        ///   - destination: final on-disk location.
        ///   - approximateSize: hint passed back through `Progress.totalBytes`
        ///     when the server doesn't advertise Content-Length.
        ///   - timeoutInterval: per-request timeout (default 5 min — matches
        ///     the previous CLI behaviour for ~400 MB DB downloads).
        ///   - resourceTimeoutInterval: full-download timeout (default 10 min).
        ///   - onProgress: optional callback per write event. Always called
        ///     on the URLSession's delegate queue (background).
        public static func download(
            from urlString: String,
            to destination: URL,
            approximateSize: Int64 = Shared.Constants.App.approximateZipSize,
            timeoutInterval: TimeInterval = 300,
            resourceTimeoutInterval: TimeInterval = 600,
            onProgress: (@Sendable (Progress) -> Void)? = nil
        ) async throws {
            guard let url = URL(string: urlString) else {
                throw Distribution.SetupError.invalidURL(urlString)
            }

            let tempURL = try await withCheckedThrowingContinuation { (
                continuation: CheckedContinuation<URL, Error>
            ) in
                let delegate = ProgressDelegate(
                    expectedSize: approximateSize,
                    onProgress: onProgress
                ) { result in
                    continuation.resume(with: result)
                }

                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = timeoutInterval
                config.timeoutIntervalForResource = resourceTimeoutInterval

                let session = URLSession(
                    configuration: config,
                    delegate: delegate,
                    delegateQueue: nil
                )
                let task = session.downloadTask(with: url)
                task.resume()
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
        }

        // MARK: - Delegate

        private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            private let expectedSize: Int64
            private let onProgress: (@Sendable (Progress) -> Void)?
            private let onComplete: (Result<URL, Error>) -> Void

            init(
                expectedSize: Int64,
                onProgress: (@Sendable (Progress) -> Void)?,
                onComplete: @escaping (Result<URL, Error>) -> Void
            ) {
                self.expectedSize = expectedSize
                self.onProgress = onProgress
                self.onComplete = onComplete
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didWriteData bytesWritten: Int64,
                totalBytesWritten: Int64,
                totalBytesExpectedToWrite: Int64
            ) {
                let total: Int64? = totalBytesExpectedToWrite > 0
                    ? totalBytesExpectedToWrite
                    : (expectedSize > 0 ? expectedSize : nil)
                onProgress?(Progress(bytesWritten: totalBytesWritten, totalBytes: total))
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didFinishDownloadingTo location: URL
            ) {
                // Copy to a stable temp file before the session invalidates.
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".zip")
                do {
                    try FileManager.default.copyItem(at: location, to: tempFile)
                    onComplete(.success(tempFile))
                } catch {
                    onComplete(.failure(error))
                }
            }

            func urlSession(
                _ session: URLSession,
                task: URLSessionTask,
                didCompleteWithError error: Error?
            ) {
                if let error {
                    onComplete(.failure(error))
                }
            }
        }
    }
}
