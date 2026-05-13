import Foundation
import SharedConstants

// MARK: - Shared.Configuration.ChangeDetection

extension Shared.Configuration {
    /// Configuration for change detection system
    public struct ChangeDetection: Codable, Sendable {
        public let enabled: Bool
        public let metadataFile: URL
        public let forceRecrawl: Bool

        public init(
            enabled: Bool = true,
            metadataFile: URL? = nil,
            forceRecrawl: Bool = false,
            outputDirectory: URL? = nil
        ) {
            self.enabled = enabled

            // If metadataFile is provided, use it
            // Otherwise, derive from outputDirectory (per-directory metadata)
            // Fall back to global metadata file if neither is provided
            if let metadataFile {
                self.metadataFile = metadataFile
            } else if let outputDirectory {
                // Store metadata.json in the output directory itself
                self.metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
            } else {
                // Global fallback
                self.metadataFile = Shared.Constants.defaultMetadataFile
            }

            self.forceRecrawl = forceRecrawl
        }
    }
}
