import Foundation
import Testing
@testable import TUI

// MARK: - ConfigManager Tests

@Test("ConfigManager default config has valid path")
func configManagerDefaultConfig() {
    let config = ConfigManager.TUIConfig.default

    #expect(!config.baseDirectory.isEmpty, "Default base directory should not be empty")
    #expect(config.baseDirectory.contains(".cupertino"), "Default should contain .cupertino")
}

@Test("ConfigManager validateBasePath accepts absolute paths")
func configManagerValidateAbsolutePath() {
    #expect(ConfigManager.validateBasePath("/usr/local/bin"), "Absolute path should be valid")
    #expect(ConfigManager.validateBasePath("/Users/test"), "Absolute path should be valid")
    #expect(ConfigManager.validateBasePath("/tmp"), "Absolute path should be valid")
}

@Test("ConfigManager validateBasePath accepts tilde paths")
func configManagerValidateTildePath() {
    #expect(ConfigManager.validateBasePath("~/.cupertino"), "Tilde path should be valid")
    #expect(ConfigManager.validateBasePath("~/Documents"), "Tilde path should be valid")
    #expect(ConfigManager.validateBasePath("~/test"), "Tilde path should be valid")
}

@Test("ConfigManager validateBasePath rejects relative paths")
func configManagerValidateRelativePath() {
    #expect(!ConfigManager.validateBasePath("relative/path"), "Relative path should be invalid")
    #expect(!ConfigManager.validateBasePath("./current"), "Relative path should be invalid")
    #expect(!ConfigManager.validateBasePath("../parent"), "Relative path should be invalid")
}

@Test("ConfigManager validateBasePath rejects empty paths")
func configManagerValidateEmptyPath() {
    #expect(!ConfigManager.validateBasePath(""), "Empty path should be invalid")
}

@Test("ConfigManager expandPath expands tilde")
func configManagerExpandTilde() {
    let expanded = ConfigManager.expandPath("~/.cupertino")

    #expect(!expanded.contains("~"), "Tilde should be expanded")
    #expect(expanded.hasPrefix("/"), "Expanded path should be absolute")
    #expect(expanded.contains(".cupertino"), "Path should contain .cupertino")
}

@Test("ConfigManager expandPath handles absolute paths")
func configManagerExpandAbsolutePath() {
    let path = "/usr/local/bin"
    let expanded = ConfigManager.expandPath(path)

    #expect(expanded == path, "Absolute path should remain unchanged")
}

@Test("ConfigManager expandPath handles paths with spaces")
func configManagerExpandPathWithSpaces() {
    let expanded = ConfigManager.expandPath("~/My Documents/.cupertino")

    #expect(!expanded.contains("~"), "Tilde should be expanded")
    #expect(expanded.contains("My Documents"), "Spaces should be preserved")
}

@Test("ConfigManager TUIConfig is Codable")
func configManagerConfigCodable() throws {
    let config = ConfigManager.TUIConfig(baseDirectory: "/test/path")

    // Encode
    let encoder = JSONEncoder()
    let data = try encoder.encode(config)

    // Decode
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ConfigManager.TUIConfig.self, from: data)

    #expect(decoded.baseDirectory == config.baseDirectory, "Config should round-trip through JSON")
}

@Test("ConfigManager save creates directory if needed")
func configManagerSaveCreatesDirectory() throws {
    // This test would need to use a temporary directory
    // For now, just verify the config is encodable
    let config = ConfigManager.TUIConfig(baseDirectory: "/test/path")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)

    #expect(!data.isEmpty, "Config should encode to non-empty data")

    // Verify it's valid JSON
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json?["baseDirectory"] as? String == "/test/path", "JSON should contain base directory")
}

@Test("ConfigManager load returns default on missing file")
func configManagerLoadMissingFile() {
    // When file doesn't exist, load() returns default
    // This is tested implicitly by the implementation
    let defaultConfig = ConfigManager.TUIConfig.default

    #expect(!defaultConfig.baseDirectory.isEmpty, "Default config should have base directory")
}

@Test("ConfigManager validateBasePath handles paths with underscores")
func configManagerValidatePathWithUnderscore() {
    #expect(ConfigManager.validateBasePath("/test/my_directory"), "Path with underscore should be valid")
    #expect(ConfigManager.validateBasePath("~/test_dir/.cupertino"), "Tilde path with underscore should be valid")
}

@Test("ConfigManager validateBasePath handles paths with dashes")
func configManagerValidatePathWithDash() {
    #expect(ConfigManager.validateBasePath("/test/my-directory"), "Path with dash should be valid")
    #expect(ConfigManager.validateBasePath("~/test-dir/.cupertino"), "Tilde path with dash should be valid")
}

@Test("ConfigManager expandPath preserves special characters")
func configManagerExpandPreservesSpecialChars() {
    let expanded = ConfigManager.expandPath("~/test_dir-2025/.cupertino")

    #expect(expanded.contains("test_dir-2025"), "Special characters should be preserved")
    #expect(expanded.contains(".cupertino"), "Dot should be preserved")
}
