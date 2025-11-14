import Foundation

// MARK: - Docsucker Configuration

/// Configuration for the Apple Documentation crawler
public struct CrawlerConfiguration: Codable, Sendable {
    public let startURL: URL
    public let allowedPrefixes: [String]
    public let maxPages: Int
    public let maxDepth: Int
    public let outputDirectory: URL
    public let requestDelay: TimeInterval
    public let retryAttempts: Int

    public init(
        startURL: URL = URL(string: "https://developer.apple.com/documentation/")!,
        allowedPrefixes: [String] = ["https://developer.apple.com/documentation"],
        maxPages: Int = 15000,
        maxDepth: Int = 15,
        outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".docsucker/docs"),
        requestDelay: TimeInterval = 0.5,
        retryAttempts: Int = 3
    ) {
        self.startURL = startURL
        self.allowedPrefixes = allowedPrefixes
        self.maxPages = maxPages
        self.maxDepth = maxDepth
        self.outputDirectory = outputDirectory
        self.requestDelay = requestDelay
        self.retryAttempts = retryAttempts
    }

    /// Load configuration from JSON file
    public static func load(from url: URL) throws -> CrawlerConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(CrawlerConfiguration.self, from: data)
    }

    /// Save configuration to JSON file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

// MARK: - Change Detection Configuration

/// Configuration for change detection system
public struct ChangeDetectionConfiguration: Codable, Sendable {
    public let enabled: Bool
    public let metadataFile: URL
    public let forceRecrawl: Bool

    public init(
        enabled: Bool = true,
        metadataFile: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".docsucker/metadata.json"),
        forceRecrawl: Bool = false
    ) {
        self.enabled = enabled
        self.metadataFile = metadataFile
        self.forceRecrawl = forceRecrawl
    }
}

// MARK: - Output Configuration

/// Configuration for output format (Markdown, PDF, etc.)
public struct OutputConfiguration: Codable, Sendable {
    public let format: OutputFormat
    public let includePDF: Bool

    public init(
        format: OutputFormat = .markdown,
        includePDF: Bool = false
    ) {
        self.format = format
        self.includePDF = includePDF
    }

    public enum OutputFormat: String, Codable, Sendable {
        case markdown
        case html
    }
}

// MARK: - Complete Configuration

/// Complete Docsucker configuration
public struct DocsuckerConfiguration: Codable, Sendable {
    public let crawler: CrawlerConfiguration
    public let changeDetection: ChangeDetectionConfiguration
    public let output: OutputConfiguration

    public init(
        crawler: CrawlerConfiguration = CrawlerConfiguration(),
        changeDetection: ChangeDetectionConfiguration = ChangeDetectionConfiguration(),
        output: OutputConfiguration = OutputConfiguration()
    ) {
        self.crawler = crawler
        self.changeDetection = changeDetection
        self.output = output
    }

    /// Load complete configuration from JSON file
    public static func load(from url: URL) throws -> DocsuckerConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(DocsuckerConfiguration.self, from: data)
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

        let defaultConfig = DocsuckerConfiguration()
        try defaultConfig.save(to: url)
    }
}
