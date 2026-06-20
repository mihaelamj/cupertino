@testable import CLI
import Foundation
import Testing

/// #657: an installed sample-code corpus can carry invalid archives (HTML
/// landing pages / partial CDN bodies saved as `.zip`) from before the
/// per-download guard, and `cupertino save --samples` keeps tripping over
/// them. The recovery sweep must park each invalid `.zip` as `.invalid`,
/// removing it from the active corpus, while leaving valid archives
/// untouched. Pinned here against a temp corpus with a known-bad payload.
@Suite("CLIImpl.quarantineInvalidSampleArchives (#657)")
struct Issue657SampleArchiveQuarantineTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-657-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Minimal valid ZIP: the end-of-central-directory record of an empty
    /// archive (`PK\x05\x06` + 18 zero bytes), which `ZipMagic.isValid`
    /// accepts as a real ZIP header.
    private func validZipData() -> Data {
        Data([0x50, 0x4b, 0x05, 0x06] + [UInt8](repeating: 0, count: 18))
    }

    @Test("an HTML landing page saved as .zip is parked as .invalid; valid archives stay")
    func quarantinesInvalidLeavesValid() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bad = dir.appendingPathComponent("accessibility.zip")
        try Data("<!DOCTYPE html><html>Apple landing page</html>".utf8).write(to: bad)
        let good = dir.appendingPathComponent("realsample.zip")
        try validZipData().write(to: good)

        let result = CLIImpl.quarantineInvalidSampleArchives(in: dir, dryRun: false)

        // Exactly the bad archive is quarantined, parked as .invalid.
        #expect(result.count == 1)
        #expect(result.first?.original.lastPathComponent == "accessibility.zip")
        #expect(result.first?.parkedAs?.lastPathComponent == "accessibility.zip.invalid")

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: bad.path)) // removed from active corpus
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("accessibility.zip.invalid").path))
        #expect(fm.fileExists(atPath: good.path)) // valid archive untouched
    }

    @Test("dry run previews the invalid archives without moving anything")
    func dryRunDoesNotMutate() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bad = dir.appendingPathComponent("updates.zip")
        try Data("not a zip".utf8).write(to: bad)

        let result = CLIImpl.quarantineInvalidSampleArchives(in: dir, dryRun: true)

        #expect(result.count == 1)
        #expect(result.first?.parkedAs == nil) // nothing parked in a dry run
        #expect(FileManager.default.fileExists(atPath: bad.path)) // left in place
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("updates.zip.invalid").path))
    }

    @Test("a clean corpus quarantines nothing (non-vacuous: the bad-payload case did)")
    func cleanCorpusNoOp() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try validZipData().write(to: dir.appendingPathComponent("a.zip"))
        try validZipData().write(to: dir.appendingPathComponent("b.zip"))

        let result = CLIImpl.quarantineInvalidSampleArchives(in: dir, dryRun: false)
        #expect(result.isEmpty)
    }

    @Test("a stale .invalid from a prior sweep does not block re-quarantine")
    func staleInvalidDoesNotBlock() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bad = dir.appendingPathComponent("samplecode.zip")
        try Data("html".utf8).write(to: bad)
        // A leftover .invalid from a previous run with the same name.
        try Data("old".utf8).write(to: dir.appendingPathComponent("samplecode.zip.invalid"))

        let result = CLIImpl.quarantineInvalidSampleArchives(in: dir, dryRun: false)
        #expect(result.first?.parkedAs?.lastPathComponent == "samplecode.zip.invalid")
        #expect(!FileManager.default.fileExists(atPath: bad.path))
    }
}
