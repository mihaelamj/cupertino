import Foundation
import SharedConstants
@testable import SharedCore
import SharedUtils
import Testing

@Suite("BinaryConfig (#211)")
struct BinaryConfigTests {
    // MARK: - load(from:)

    @Test("nil search directory yields empty config")
    func nilDirectory() {
        let config = Shared.BinaryConfig.load(from: nil)
        #expect(config.baseDirectory == nil)
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("missing config file falls through to empty config")
    func missingFile() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = Shared.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == nil)
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("valid JSON with absolute baseDirectory parses correctly")
    func absolutePath() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: #"{"baseDirectory":"/var/tmp/cupertino-dev"}"#)
        let config = Shared.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == "/var/tmp/cupertino-dev")
        #expect(config.resolvedBaseDirectory?.path == "/var/tmp/cupertino-dev")
    }

    @Test("tilde in baseDirectory expands to home")
    func tildeExpansion() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: #"{"baseDirectory":"~/.cupertino-dev"}"#)
        let config = Shared.BinaryConfig.load(from: dir)
        let expected = ("~/.cupertino-dev" as NSString).expandingTildeInPath
        #expect(config.resolvedBaseDirectory?.path == expected)
        #expect(config.resolvedBaseDirectory?.path.hasPrefix("~") == false)
    }

    @Test("missing baseDirectory key is allowed")
    func missingKey() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: "{}")
        let config = Shared.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == nil)
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("empty-string baseDirectory resolves to nil")
    func emptyString() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: #"{"baseDirectory":""}"#)
        let config = Shared.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == "")
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("invalid JSON falls through silently to empty config")
    func invalidJSON() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: "{ this is not valid")
        let config = Shared.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == nil)
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("unknown extra keys are ignored")
    func extraKeys() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(
            in: dir,
            contents: #"{"baseDirectory":"/tmp/x","futureKey":"ignored","another":42}"#
        )
        let config = Shared.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == "/tmp/x")
    }

    @Test("file name constant is cupertino.config.json")
    func fileNameConstant() {
        #expect(Shared.BinaryConfig.fileName == "cupertino.config.json")
    }

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BinaryConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writeConfig(in dir: URL, contents: String) throws {
        let url = dir.appendingPathComponent(Shared.BinaryConfig.fileName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
