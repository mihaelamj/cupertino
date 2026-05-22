@testable import Distribution
import Foundation
import SharedConstants
import Testing

// MARK: - Status classification (#168, lifted to Distribution in #246)

@Suite("Distribution.InstalledVersion.classify")
struct InstalledVersionStatusTests {
    // Descriptor fixtures (#248 first cut: classify takes Set<Shared.Models.DatabaseDescriptor>).
    private static let searchDB = Shared.Models.DatabaseDescriptor(
        id: "search",
        filename: Shared.Constants.FileName.searchDatabase,
        displayName: "Documentation"
    )
    private static let samplesDB = Shared.Models.DatabaseDescriptor(
        id: "samples",
        filename: Shared.Constants.FileName.samplesDatabase,
        displayName: "Sample code"
    )
    private static let packagesDB = Shared.Models.DatabaseDescriptor(
        id: "packages",
        filename: Shared.Constants.FileName.packagesIndexDatabase,
        displayName: "Packages"
    )
    private static let requiredAll: Set<Shared.Models.DatabaseDescriptor> = [searchDB, samplesDB, packagesDB]

    @Test("Missing search.db classifies as .missing")
    func missingSearch() {
        let status = Distribution.InstalledVersion.classify(
            present: [Self.samplesDB, Self.packagesDB],
            required: Self.requiredAll,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("Missing samples.db classifies as .missing")
    func missingSamples() {
        let status = Distribution.InstalledVersion.classify(
            present: [Self.searchDB, Self.packagesDB],
            required: Self.requiredAll,
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
            present: [Self.searchDB, Self.samplesDB],
            required: Self.requiredAll,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("All DBs missing also classifies as .missing")
    func allMissing() {
        let status = Distribution.InstalledVersion.classify(
            present: [],
            required: Self.requiredAll,
            installedVersion: nil,
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("All DBs present + nil version file = .unknown (legacy install)")
    func unknownLegacyInstall() {
        let status = Distribution.InstalledVersion.classify(
            present: [Self.searchDB, Self.samplesDB, Self.packagesDB],
            required: Self.requiredAll,
            installedVersion: nil,
            currentVersion: "0.9.0"
        )
        #expect(status == .unknown(current: "0.9.0"))
    }

    @Test("All DBs present + matching version = .current")
    func currentDBs() {
        let status = Distribution.InstalledVersion.classify(
            present: [Self.searchDB, Self.samplesDB, Self.packagesDB],
            required: Self.requiredAll,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .current(version: "0.9.0"))
    }

    @Test("All DBs present + different version = .stale")
    func staleDBs() {
        let status = Distribution.InstalledVersion.classify(
            present: [Self.searchDB, Self.samplesDB, Self.packagesDB],
            required: Self.requiredAll,
            installedVersion: "0.8.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .stale(installed: "0.8.0", current: "0.9.0"))
    }

    @Test("Single-DB required set + that DB present = .current (descriptor-set generality, #248)")
    func singleDBSetup() {
        // Confirms the signature is genuinely DB-count-agnostic, not just
        // a three-DB shim. A future 1-DB or 4-DB install works without
        // touching this function.
        let status = Distribution.InstalledVersion.classify(
            present: [Self.searchDB],
            required: [Self.searchDB],
            installedVersion: "1.2.0",
            currentVersion: "1.2.0"
        )
        #expect(status == .current(version: "1.2.0"))
    }
}

// MARK: - Release.Version file read/write

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
