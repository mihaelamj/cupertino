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

        public init(
            crawler: Crawler = Crawler(),
            changeDetection: ChangeDetection = ChangeDetection(),
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

        /// Create default configuration file if it doesn't exist
        public static func createDefaultIfNeeded(at url: URL) throws {
            guard !FileManager.default.fileExists(atPath: url.path) else {
                return
            }

            let defaultConfig = Configuration()
            try defaultConfig.save(to: url)
        }
    }
}
