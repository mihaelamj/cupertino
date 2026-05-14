import Foundation
import SharedConstants

// MARK: - Shared.Configuration.ChangeDetection

extension Shared.Configuration {
    /// Configuration for change detection system.
    ///
    /// `outputDirectory` is the per-crawl base where `metadata.json` lives;
    /// the caller is responsible for resolving it at the composition root
    /// (via `Shared.Paths.live().docsDirectory` or a test temp dir).
    /// Pre-#535 a `nil` outputDirectory fell back to
    /// `Shared.Constants.defaultMetadataFile`, which routed through the
    /// `BinaryConfig.shared` Singleton (Seemann 2011 ch. 5 Service
    /// Locator). Strict DI removes that path: the caller always supplies
    /// the directory it wants.
    public struct ChangeDetection: Codable, Sendable {
        public let enabled: Bool
        public let metadataFile: URL
        public let forceRecrawl: Bool

        public init(
            enabled: Bool = true,
            metadataFile: URL? = nil,
            forceRecrawl: Bool = false,
            outputDirectory: URL
        ) {
            self.enabled = enabled

            // If metadataFile is provided, use it. Otherwise derive
            // per-directory metadata under outputDirectory.
            if let metadataFile {
                self.metadataFile = metadataFile
            } else {
                self.metadataFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.metadata)
            }

            self.forceRecrawl = forceRecrawl
        }
    }
}
