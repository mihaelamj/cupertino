import Foundation
import SharedConstants

// MARK: - Sample Core Downloader Error

extension Sample.Core.Downloader {
    public enum Error: Swift.Error {
        case downloadLinkNotFound(String)
        case downloadFailed(String)
        case invalidResponse
    }
}
