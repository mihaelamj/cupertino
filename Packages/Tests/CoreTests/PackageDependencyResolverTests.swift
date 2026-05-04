// swiftlint:disable use_data_constructor_over_string_member non_optional_string_data_conversion
@testable import Core
import Foundation
import Testing

// MARK: - GitHub URL parsing

@Test("parseGitHubRepo: plain https URL")
func parseGitHubRepoPlainHTTPS() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/apple/swift-nio")
    #expect(parsed?.owner == "apple")
    #expect(parsed?.repo == "swift-nio")
}

@Test("parseGitHubRepo: strips trailing .git")
func parseGitHubRepoStripsGitSuffix() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/apple/swift-nio.git")
    #expect(parsed?.owner == "apple")
    #expect(parsed?.repo == "swift-nio")
}

@Test("parseGitHubRepo: SSH form")
func parseGitHubRepoSSHForm() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("git@github.com:apple/swift-nio.git")
    #expect(parsed?.owner == "apple")
    #expect(parsed?.repo == "swift-nio")
}

@Test("parseGitHubRepo: trailing slash ignored")
func parseGitHubRepoTrailingSlash() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/apple/swift-nio/")
    #expect(parsed?.owner == "apple")
    #expect(parsed?.repo == "swift-nio")
}

@Test("parseGitHubRepo: strips tree/blob paths")
func parseGitHubRepoStripsTreePath() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/apple/swift-nio/tree/main")
    #expect(parsed?.owner == "apple")
    #expect(parsed?.repo == "swift-nio")
}

@Test("parseGitHubRepo: preserves case")
func parseGitHubRepoPreservesCase() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/Apple/Swift-NIO")
    #expect(parsed?.owner == "Apple")
    #expect(parsed?.repo == "Swift-NIO")
}

@Test("parseGitHubRepo: leading/trailing whitespace trimmed")
func parseGitHubRepoTrimsWhitespace() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("  https://github.com/apple/swift-nio  ")
    #expect(parsed?.owner == "apple")
    #expect(parsed?.repo == "swift-nio")
}

@Test("parseGitHubRepo: rejects GitLab")
func parseGitHubRepoRejectsGitLab() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://gitlab.com/foo/bar")
    #expect(parsed == nil)
}

@Test("parseGitHubRepo: rejects Bitbucket")
func parseGitHubRepoRejectsBitbucket() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://bitbucket.org/foo/bar")
    #expect(parsed == nil)
}

@Test("parseGitHubRepo: rejects URL with missing repo")
func parseGitHubRepoRejectsMissingRepo() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/apple")
    #expect(parsed == nil)
}

@Test("parseGitHubRepo: rejects empty path")
func parseGitHubRepoRejectsEmptyPath() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/")
    #expect(parsed == nil)
}

@Test("parseGitHubRepo: rejects invalid characters in slug")
func parseGitHubRepoRejectsInvalidCharacters() {
    let parsed = Core.PackageDependencyResolver.parseGitHubRepo("https://github.com/apple/swift nio")
    #expect(parsed == nil)
}

// MARK: - Package.resolved parsing

@Test("parsePackageResolvedLocations: v2/v3 shape with location")
func parseResolvedV2() throws {
    let json = """
    {
      "pins": [
        {"identity":"swift-nio","kind":"remoteSourceControl","location":"https://github.com/apple/swift-nio","state":{"revision":"abc","version":"2.0.0"}},
        {"identity":"swift-log","kind":"remoteSourceControl","location":"https://github.com/apple/swift-log.git","state":{"revision":"def","version":"1.0.0"}}
      ],
      "version": 2
    }
    """.data(using: .utf8)!
    let locations = try #require(Core.PackageDependencyResolver.parsePackageResolvedLocations(json))
    #expect(locations == [
        "https://github.com/apple/swift-nio",
        "https://github.com/apple/swift-log.git",
    ])
}

@Test("parsePackageResolvedLocations: v1 shape with pins nested under object")
func parseResolvedV1NestedPins() throws {
    // SPM v1 Package.resolved keeps pins under `object.pins`; v2/v3 hoisted them to root.
    let json = """
    {
      "object": {
        "pins": [
          {"package":"swift-nio","repositoryURL":"https://github.com/apple/swift-nio","state":{"revision":"abc"}}
        ]
      },
      "version": 1
    }
    """.data(using: .utf8)!
    let locations = try #require(Core.PackageDependencyResolver.parsePackageResolvedLocations(json))
    #expect(locations == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageResolvedLocations: v1 shape with pins at root (older tooling)")
func parseResolvedV1RootPins() throws {
    let json = """
    {
      "pins": [
        {"package":"swift-nio","repositoryURL":"https://github.com/apple/swift-nio","state":{"revision":"abc"}}
      ],
      "version": 1
    }
    """.data(using: .utf8)!
    let locations = try #require(Core.PackageDependencyResolver.parsePackageResolvedLocations(json))
    #expect(locations == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageResolvedLocations: v1 with nested object.repositoryURL")
func parseResolvedNestedObject() throws {
    let json = """
    {
      "pins": [
        {"package":"swift-nio","object":{"repositoryURL":"https://github.com/apple/swift-nio","state":{"revision":"abc"}}}
      ],
      "version": 1
    }
    """.data(using: .utf8)!
    let locations = try #require(Core.PackageDependencyResolver.parsePackageResolvedLocations(json))
    #expect(locations == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageResolvedLocations: mixed v1+v2 pins stays tolerant")
func parseResolvedMixedShapes() throws {
    let json = """
    {
      "pins": [
        {"identity":"swift-nio","location":"https://github.com/apple/swift-nio"},
        {"package":"swift-log","repositoryURL":"https://github.com/apple/swift-log"}
      ]
    }
    """.data(using: .utf8)!
    let locations = try #require(Core.PackageDependencyResolver.parsePackageResolvedLocations(json))
    #expect(locations == [
        "https://github.com/apple/swift-nio",
        "https://github.com/apple/swift-log",
    ])
}

@Test("parsePackageResolvedLocations: empty pins yields empty array")
func parseResolvedEmptyPins() throws {
    let json = """
    {"pins": []}
    """.data(using: .utf8)!
    let locations = try #require(Core.PackageDependencyResolver.parsePackageResolvedLocations(json))
    #expect(locations.isEmpty)
}

@Test("parsePackageResolvedLocations: missing pins key returns nil")
func parseResolvedMissingPins() {
    let json = """
    {"version": 2}
    """.data(using: .utf8)!
    #expect(Core.PackageDependencyResolver.parsePackageResolvedLocations(json) == nil)
}

@Test("parsePackageResolvedLocations: non-dict root returns nil")
func parseResolvedNonDictRoot() {
    let json = "[]".data(using: .utf8)!
    #expect(Core.PackageDependencyResolver.parsePackageResolvedLocations(json) == nil)
}

@Test("parsePackageResolvedLocations: malformed JSON returns nil")
func parseResolvedMalformedJSON() {
    let junk = Data([0x00, 0xff, 0x42])
    #expect(Core.PackageDependencyResolver.parsePackageResolvedLocations(junk) == nil)
}

@Test("parsePackageResolvedLocations: pin without any URL key is skipped")
func parseResolvedPinWithoutURL() throws {
    let json = """
    {
      "pins": [
        {"identity":"mystery","kind":"remoteSourceControl"},
        {"identity":"swift-nio","location":"https://github.com/apple/swift-nio"}
      ]
    }
    """.data(using: .utf8)!
    let locations = try #require(Core.PackageDependencyResolver.parsePackageResolvedLocations(json))
    #expect(locations == ["https://github.com/apple/swift-nio"])
}

// MARK: - Package.swift parsing

@Test("parsePackageSwiftURLs: simple single-line .package(url:from:)")
func parsePackageSwiftSimple() {
    let source = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "Example",
        dependencies: [
            .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
        ]
    )
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageSwiftURLs: multi-line .package with nested version predicate")
func parsePackageSwiftMultiLineNested() {
    let source = """
    let package = Package(
        name: "Example",
        dependencies: [
            .package(
                url: "https://github.com/apple/swift-log",
                .upToNextMajor(from: "1.0.0")
            ),
        ]
    )
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == ["https://github.com/apple/swift-log"])
}

@Test("parsePackageSwiftURLs: multiple dependencies in one manifest")
func parsePackageSwiftMultiple() {
    let source = """
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log", branch: "main"),
        .package(url: "https://github.com/apple/swift-metrics", exact: "2.0.0"),
    ]
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == [
        "https://github.com/apple/swift-nio",
        "https://github.com/apple/swift-log",
        "https://github.com/apple/swift-metrics",
    ])
}

@Test("parsePackageSwiftURLs: legacy .package(name:url:) form")
func parsePackageSwiftLegacyNamedForm() {
    let source = """
    dependencies: [
        .package(name: "SwiftNIO", url: "https://github.com/apple/swift-nio", from: "2.0.0"),
    ]
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageSwiftURLs: .package(path:) local deps are ignored")
func parsePackageSwiftLocalPathIgnored() {
    let source = """
    dependencies: [
        .package(path: "../LocalLibrary"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
    ]
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageSwiftURLs: commented-out .package is skipped")
func parsePackageSwiftCommentSkipped() {
    let source = """
    dependencies: [
        // .package(url: "https://github.com/apple/swift-atomics", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
    ]
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageSwiftURLs: manifest with no dependencies")
func parsePackageSwiftNoDependencies() {
    let source = """
    import PackageDescription

    let package = Package(
        name: "Example",
        targets: [.target(name: "Example")]
    )
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls.isEmpty)
}

@Test("parsePackageSwiftURLs: empty file")
func parsePackageSwiftEmpty() {
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(Data())
    #expect(urls.isEmpty)
}

@Test("parsePackageSwiftURLs: non-UTF8 bytes yields empty")
func parsePackageSwiftBinaryInput() {
    let bytes = Data([0xff, 0xfe, 0xfd])
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(bytes)
    #expect(urls.isEmpty)
}

@Test("parsePackageSwiftURLs: .package(url:) with range version")
func parsePackageSwiftRangeVersion() {
    let source = """
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", "2.0.0"..<"3.0.0"),
    ]
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == ["https://github.com/apple/swift-nio"])
}

@Test("parsePackageSwiftURLs: inline comment does not swallow the URL's //")
func parsePackageSwiftInlineCommentRespectsStringLiteral() {
    // Regression: a dumb `//` strip truncates `https://github.com/...` to `https:`
    // and then downstream regex reaches into the next line for the closing quote.
    let source = """
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"), // TODO: upgrade
    ]
    """.data(using: .utf8)!
    let urls = Core.PackageDependencyResolver.parsePackageSwiftURLs(source)
    #expect(urls == ["https://github.com/apple/swift-nio"])
}

@Test("stripLineComment: preserves // inside string literal")
func stripLineCommentPreservesURLInString() {
    let input: Substring = #"    .package(url: "https://github.com/apple/swift-nio", from: "2.0.0")"#[...]
    let stripped = Core.PackageDependencyResolver.stripLineComment(input)
    #expect(stripped == String(input))
}

@Test("stripLineComment: strips trailing // comment")
func stripLineCommentStripsTrailing() {
    let input: Substring = #"    let x = 5  // this is a comment"#[...]
    let stripped = Core.PackageDependencyResolver.stripLineComment(input)
    #expect(stripped == "    let x = 5  ")
}

@Test("stripLineComment: strips whole-line // comment")
func stripLineCommentStripsWholeLine() {
    let input: Substring = "// entirely a comment"[...]
    let stripped = Core.PackageDependencyResolver.stripLineComment(input)
    #expect(stripped == "")
}
