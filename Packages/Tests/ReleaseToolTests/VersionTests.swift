@testable import ReleaseTool
import Testing

// MARK: - Release.Version Parsing Tests

@Suite("Release.Version Parsing")
struct VersionParsingTests {
    @Test("Parse valid version string")
    func parseValidVersion() {
        let version = Release.Version("1.2.3")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
    }

    @Test("Parse version with v prefix")
    func parseVersionWithPrefix() {
        let version = Release.Version("v1.2.3")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
    }

    @Test("Reject invalid version string")
    func rejectInvalidVersion() {
        #expect(Release.Version("invalid") == nil)
        #expect(Release.Version("1.2") == nil)
        #expect(Release.Version("1.2.3.4") == nil)
        #expect(Release.Version("") == nil)
        #expect(Release.Version("a.b.c") == nil)
    }

    @Test("Release.Version description")
    func versionDescription() {
        let version = Release.Version(major: 1, minor: 2, patch: 3)
        #expect(version.description == "1.2.3")
    }

    @Test("Release.Version tag")
    func versionTag() {
        let version = Release.Version(major: 1, minor: 2, patch: 3)
        #expect(version.tag == "v1.2.3")
    }
}

// MARK: - Release.Version Bumping Tests

@Suite("Release.Version Bumping")
struct VersionBumpingTests {
    @Test("Bump patch version")
    func bumpPatch() {
        let version = Release.Version(major: 1, minor: 2, patch: 3)
        let bumped = version.bumped(.patch)
        #expect(bumped.major == 1)
        #expect(bumped.minor == 2)
        #expect(bumped.patch == 4)
    }

    @Test("Bump minor version resets patch")
    func bumpMinor() {
        let version = Release.Version(major: 1, minor: 2, patch: 3)
        let bumped = version.bumped(.minor)
        #expect(bumped.major == 1)
        #expect(bumped.minor == 3)
        #expect(bumped.patch == 0)
    }

    @Test("Bump major version resets minor and patch")
    func bumpMajor() {
        let version = Release.Version(major: 1, minor: 2, patch: 3)
        let bumped = version.bumped(.major)
        #expect(bumped.major == 2)
        #expect(bumped.minor == 0)
        #expect(bumped.patch == 0)
    }

    @Test("Bump from zero version")
    func bumpFromZero() {
        let version = Release.Version(major: 0, minor: 0, patch: 0)

        let patchBumped = version.bumped(.patch)
        #expect(patchBumped.description == "0.0.1")

        let minorBumped = version.bumped(.minor)
        #expect(minorBumped.description == "0.1.0")

        let majorBumped = version.bumped(.major)
        #expect(majorBumped.description == "1.0.0")
    }
}

// MARK: - Release.Version.BumpType Tests

@Suite("Release.Version.BumpType Parsing")
struct BumpTypeTests {
    @Test("Parse bump types from strings")
    func parseBumpTypes() {
        #expect(Release.Version.BumpType(rawValue: "major") == .major)
        #expect(Release.Version.BumpType(rawValue: "minor") == .minor)
        #expect(Release.Version.BumpType(rawValue: "patch") == .patch)
    }

    @Test("Reject invalid bump type")
    func rejectInvalidBumpType() {
        #expect(Release.Version.BumpType(rawValue: "invalid") == nil)
        #expect(Release.Version.BumpType(rawValue: "") == nil)
        #expect(Release.Version.BumpType(rawValue: "MAJOR") == nil) // case sensitive
    }
}
