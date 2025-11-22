import Foundation
import Shared

/// Manages TUI configuration persistence
enum ConfigManager {
    private static let configFile = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".cupertino")
        .appendingPathComponent("tui-config.json")

    struct TUIConfig: Codable {
        var baseDirectory: String

        static let `default` = TUIConfig(
            baseDirectory: FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".cupertino")
                .path
        )
    }

    /// Load configuration from disk
    static func load() -> TUIConfig {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: configFile)
            let config = try JSONDecoder().decode(TUIConfig.self, from: data)
            return config
        } catch {
            // If loading fails, return default
            return .default
        }
    }

    /// Save configuration to disk
    static func save(_ config: TUIConfig) throws {
        // Ensure config directory exists
        let configDir = configFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: configDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFile)
    }

    /// Validate base directory path
    static func validateBasePath(_ path: String) -> Bool {
        // Expand tilde
        let expandedPath = NSString(string: path).expandingTildeInPath

        // Check if it's an absolute path or can be made absolute
        guard !expandedPath.isEmpty else { return false }

        // Allow paths starting with / or ~
        return expandedPath.hasPrefix("/") || path.hasPrefix("~")
    }

    /// Expand tilde in path
    static func expandPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
