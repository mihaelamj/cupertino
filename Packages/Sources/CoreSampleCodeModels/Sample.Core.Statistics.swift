import Foundation
import SharedConstants

// MARK: - Sample Core Statistics

extension Sample.Core {
    public struct Statistics: Sendable {
        public var totalSamples: Int = 0
        public var downloadedSamples: Int = 0
        public var skippedSamples: Int = 0
        public var errors: Int = 0
        /// #657 — count of sample archives whose HTTP body downloaded
        /// successfully (HTTP 200) but failed the ZIP magic-signature
        /// check on disk. Apple's CDN sometimes returns an HTML landing
        /// page or partial body with HTTP 200; pre-#657 those slipped
        /// straight into `~/.cupertino/sample-code/` and tripped up
        /// `cupertino save --samples` at index time. They're now
        /// renamed to `<filename>.invalid` and tallied separately
        /// from `downloadedSamples` so the fetch summary surfaces the
        /// failure mode rather than hiding it under the success bucket.
        public var invalidDownloads: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public init(
            totalSamples: Int = 0,
            downloadedSamples: Int = 0,
            skippedSamples: Int = 0,
            errors: Int = 0,
            invalidDownloads: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.totalSamples = totalSamples
            self.downloadedSamples = downloadedSamples
            self.skippedSamples = skippedSamples
            self.errors = errors
            self.invalidDownloads = invalidDownloads
            self.startTime = startTime
            self.endTime = endTime
        }

        public var duration: TimeInterval? {
            guard let start = startTime, let end = endTime else {
                return nil
            }
            return end.timeIntervalSince(start)
        }
    }
}
