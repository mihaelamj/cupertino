@testable import Distribution
import Foundation
@testable import SharedCore
import Testing
import SharedConstants

// MARK: - Status classification (#168, lifted to Distribution in #246)

@Suite("Distribution.InstalledVersion.classify")
struct InstalledVersionStatusTests {
    @Test("Missing search.db classifies as .missing")
    func missingSearch() {
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: false,
            samplesDBExists: true,
            packagesDBExists: true,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("Missing samples.db classifies as .missing")
    func missingSamples() {
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: true,
            samplesDBExists: false,
            packagesDBExists: true,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("Missing packages.db classifies as .missing (#246 fix)")
    func missingPackages() {
        // Pre-#246 the status enum ignored packages.db; cupertino setup
        // would report .current even when packages.db hadn't been
        // downloaded yet. Now any missing DB → .missing.
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: true,
            samplesDBExists: true,
            packagesDBExists: false,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("All DBs missing also classifies as .missing")
    func allMissing() {
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: false,
            samplesDBExists: false,
            packagesDBExists: false,
            installedVersion: nil,
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("All DBs present + nil version file = .unknown (legacy install)")
    func unknownLegacyInstall() {
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: true,
            samplesDBExists: true,
            packagesDBExists: true,
            installedVersion: nil,
            currentVersion: "0.9.0"
        )
        #expect(status == .unknown(current: "0.9.0"))
    }

    @Test("All DBs present + matching version = .current")
    func currentDBs() {
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: true,
            samplesDBExists: true,
            packagesDBExists: true,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .current(version: "0.9.0"))
    }

    @Test("All DBs present + different version = .stale")
    func staleDBs() {
        let status = Distribution.InstalledVersion.classify(
            searchDBExists: true,
            samplesDBExists: true,
            packagesDBExists: true,
            installedVersion: "0.8.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .stale(installed: "0.8.0", current: "0.9.0"))
    }
}

// MARK: - Version file read/write

@Suite("Distribution.InstalledVersion file helpers")
struct InstalledVersionFileTests {
    private static func tempBaseDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-setup-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Read returns nil when the version file is absent")
    func readMissingReturnsNil() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Distribution.InstalledVersion.read(in: dir) == nil)
    }

    @Test("Write then read round-trips the version string")
    func writeThenRead() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Distribution.InstalledVersion.write("0.9.0", in: dir)
        #expect(Distribution.InstalledVersion.read(in: dir) == "0.9.0")
    }

    @Test("Read trims surrounding whitespace and newlines")
    func readTrimsWhitespace() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Shared.Constants.FileName.setupVersionFile)
        try "  0.9.0  \n".write(to: url, atomically: true, encoding: .utf8)
        #expect(Distribution.InstalledVersion.read(in: dir) == "0.9.0")
    }

    @Test("Read returns nil for an empty/whitespace-only file")
    func readEmptyFileReturnsNil() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Shared.Constants.FileName.setupVersionFile)
        try "   \n\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(Distribution.InstalledVersion.read(in: dir) == nil)
    }

    @Test("Write overwrites the existing version")
    func writeOverwrites() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Distribution.InstalledVersion.write("0.8.0", in: dir)
        try Distribution.InstalledVersion.write("0.9.0", in: dir)
        #expect(Distribution.InstalledVersion.read(in: dir) == "0.9.0")
    }
}
