import Foundation
import SharedConstants
import Testing

@Suite("BinaryConfig (#211)")
struct BinaryConfigTests {
    // MARK: - load(from:)

    @Test("nil search directory yields empty config")
    func nilDirectory() {
        let config = Shared.Constants.BinaryConfig.load(from: nil)
        #expect(config.baseDirectory == nil)
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("missing config file falls through to empty config")
    func missingFile() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = Shared.Constants.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == nil)
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("valid JSON with absolute baseDirectory parses correctly")
    func absolutePath() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: #"{"baseDirectory":"/var/tmp/cupertino-dev"}"#)
        let config = Shared.Constants.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == "/var/tmp/cupertino-dev")
        #expect(config.resolvedBaseDirectory?.path == "/var/tmp/cupertino-dev")
    }

    @Test("tilde in baseDirectory expands to home")
    func tildeExpansion() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: #"{"baseDirectory":"~/.cupertino-dev"}"#)
        let config = Shared.Constants.BinaryConfig.load(from: dir)
        let expected = ("~/.cupertino-dev" as NSString).expandingTildeInPath
        #expect(config.resolvedBaseDirectory?.path == expected)
        #expect(config.resolvedBaseDirectory?.path.hasPrefix("~") == false)
    }

    @Test("missing baseDirectory key is allowed")
    func missingKey() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: "{}")
        let config = Shared.Constants.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == nil)
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("empty-string baseDirectory resolves to nil")
    func emptyString() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: #"{"baseDirectory":""}"#)
        let config = Shared.Constants.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == "")
        #expect(config.resolvedBaseDirectory == nil)
    }

    @Test("invalid JSON falls through silently to empty config")
    func invalidJSON() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeConfig(in: dir, contents: "{ this is not valid")
        let config = Shared.Constants.BinaryConfig.load(from: dir)
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
        let config = Shared.Constants.BinaryConfig.load(from: dir)
        #expect(config.baseDirectory == "/tmp/x")
    }

    @Test("file name constant is cupertino.config.json")
    func fileNameConstant() {
        #expect(Shared.Constants.BinaryConfig.fileName == "cupertino.config.json")
    }

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BinaryConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writeConfig(in dir: URL, contents: String) throws {
        let url = dir.appendingPathComponent(Shared.Constants.BinaryConfig.fileName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - #675 — provenance classification + isolation-by-default resolution

@Suite("BinaryConfig.Provenance (#675 isolation by default)")
struct BinaryConfigProvenanceTests {
    // MARK: - classify(executablePath:)

    @Test(
        "Brew install prefixes classify as .brewInstalled",
        arguments: [
            "/opt/homebrew/bin/cupertino",
            "/opt/homebrew/Cellar/cupertino/1.1.0/bin/cupertino",
            "/usr/local/bin/cupertino",
            "/usr/local/Cellar/cupertino/1.0.2/bin/cupertino",
            "/home/linuxbrew/.linuxbrew/bin/cupertino",
            "/home/linuxbrew/.linuxbrew/Cellar/cupertino/1.1.0/bin/cupertino",
        ]
    )
    func brewPrefixesClassifyAsBrewInstalled(path: String) {
        #expect(Shared.Constants.BinaryConfig.classify(executablePath: path) == .brewInstalled)
    }

    @Test(
        "Non-brew paths classify as .other",
        arguments: [
            // SwiftPM dev-build paths — the headline case #675 fixes.
            "/Volumes/Code/DeveloperExt/public/cupertino/Packages/.build/release/cupertino",
            "/Users/mmj/.cupertino/Packages/.build/debug/cupertino",
            // CI workspace
            "/Users/runner/work/cupertino/cupertino/Packages/.build/release/cupertino",
            // Manually copied executable
            "/tmp/cupertino",
            "/Users/mmj/Desktop/cupertino-test/cupertino",
            // System bin paths that AREN'T brew-managed
            "/usr/bin/cupertino",
            "/usr/sbin/cupertino",
            "/sbin/cupertino",
            // Empty / nonsense
            "",
            "cupertino",
        ]
    )
    func nonBrewPathsClassifyAsOther(path: String) {
        #expect(Shared.Constants.BinaryConfig.classify(executablePath: path) == .other)
    }

    @Test("Look-alike paths that contain a brew prefix substring but don't start with it classify as .other")
    func brewSubstringNotPrefixIsNotBrew() {
        // Defensive: prefix-match must NOT trip on substrings deeper in the path.
        let lookAlike = "/Users/mmj/work/opt/homebrew/bin/cupertino" // /opt/homebrew/bin appears AFTER /Users/…
        #expect(Shared.Constants.BinaryConfig.classify(executablePath: lookAlike) == .other)
    }

    // MARK: - Paths(binaryConfig:provenance:) default resolution

    @Test("Explicit conf-file override wins regardless of provenance (brew + non-brew)")
    func confOverrideWinsForAllProvenances() {
        let override = "/var/tmp/cupertino-explicit-override"
        let conf = Shared.Constants.BinaryConfig(baseDirectory: override)

        let brewPaths = Shared.Paths(binaryConfig: conf, provenance: .brewInstalled)
        #expect(brewPaths.baseDirectory.path == override)

        let devPaths = Shared.Paths(binaryConfig: conf, provenance: .other)
        #expect(devPaths.baseDirectory.path == override)
    }

    @Test("Brew-installed binary + no conf override → ~/.cupertino/ (production default)")
    func brewProvenanceDefault() {
        let paths = Shared.Paths(
            binaryConfig: Shared.Constants.BinaryConfig(),
            provenance: .brewInstalled
        )
        let expectedSuffix = "/" + Shared.Constants.baseDirectoryName // ".cupertino"
        #expect(paths.baseDirectory.path.hasSuffix(expectedSuffix))
        #expect(paths.baseDirectory.path.hasSuffix(".cupertino-dev") == false)
    }

    @Test("Non-brew binary + no conf override → ~/.cupertino-dev/ (isolation default — #675 headline)")
    func otherProvenanceDefault() {
        let paths = Shared.Paths(
            binaryConfig: Shared.Constants.BinaryConfig(),
            provenance: .other
        )
        let expectedSuffix = "/" + Shared.Constants.devBaseDirectoryName // ".cupertino-dev"
        #expect(paths.baseDirectory.path.hasSuffix(expectedSuffix))
    }

    @Test("Dev-isolated default directory name is .cupertino-dev (pins the convention #675)")
    func devDirNameIsCupertinoDev() {
        #expect(Shared.Constants.devBaseDirectoryName == ".cupertino-dev")
    }
}
