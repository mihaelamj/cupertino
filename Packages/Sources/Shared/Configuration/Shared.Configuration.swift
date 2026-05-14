import Foundation
import SharedConstants
import SharedUtils

// MARK: - Shared.Configuration (aggregate)

extension Shared {
    /// Complete Cupertino configuration tree. Hosts the three sub-configurations
    /// `Crawler`, `ChangeDetection`, `Output`, plus the `DiscoveryMode` enum
    /// that the crawler uses.
    public struct Configuration: Codable, Sendable {
        public let crawler: Crawler
        public let changeDetection: ChangeDetection
        public let output: Output

        /// Strict-DI memberwise initialiser (#535). The previous shape
        /// defaulted `Crawler()` / `ChangeDetection()` / `Output()` which
        /// each reached for `Shared.Constants.defaultX` through
        /// `BinaryConfig.shared` (Service Locator). The caller now passes
        /// each sub-configuration explicitly; the composition root resolves
        /// `outputDirectory` once via `Shared.Paths.live().docsDirectory`
        /// and threads it down.
        public init(
            crawler: Crawler,
            changeDetection: ChangeDetection,
            output: Output = Output()
        ) {
            self.crawler = crawler
            self.changeDetection = changeDetection
            self.output = output
        }

        /// Load complete configuration from JSON file
        public static func load(from url: URL) throws -> Shared.Configuration {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(Shared.Configuration.self, from: data)
        }

        /// Save complete configuration to JSON file
        public func save(to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url)
        }

        /// Create default configuration file if it doesn't exist.
        ///
        /// `outputDirectory` is the per-install docs base — the resolved
        /// path the composition root would otherwise pass to
        /// `Crawler(outputDirectory:)`. Pre-#535 this defaulted to the
        /// `BinaryConfig.shared` Singleton path; now the caller supplies it.
        public static func createDefaultIfNeeded(at url: URL, outputDirectory: URL) throws {
            guard !FileManager.default.fileExists(atPath: url.path) else {
                return
            }

            let defaultConfig = Configuration(
                crawler: Crawler(outputDirectory: outputDirectory),
                changeDetection: ChangeDetection(outputDirectory: outputDirectory)
            )
            try defaultConfig.save(to: url)
        }
    }
}
