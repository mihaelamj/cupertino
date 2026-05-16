import Foundation
import SharedConstants
import Testing

// MARK: - #657 — Shared.Utils.ZipMagic.isValid validates 4-byte ZIP signature

//
// Background: Apple's CDN occasionally returns an HTML landing page or
// partial body with HTTP 200 (transient CDN issues, redirect chains,
// auth gates). The `cupertino fetch --type samples` path trusted the
// HTTP status code and saved the body to disk with a `.zip`
// extension. Main's 2026-05-16 post-#653 retest found 3 such
// corruptions on the live corpus (`accessibility.zip`,
// `appintents.zip`, `ios-ipados-release-notes.zip` — all HTML landing
// pages saved as zips).
//
// `Shared.Utils.ZipMagic.isValid(at:)` reads the first 4 bytes of the
// file and accepts one of three PKWARE APPNOTE signature prefixes:
// `PK\x03\x04` (local file header, common case), `PK\x05\x06`
// (end-of-central-directory only — empty archive), `PK\x07\x08`
// (spanned archive). Returns false for missing files, permission
// denied, truncated reads (<4 bytes), and any non-PK header.
//
// 4 bytes of I/O per file is ~3 orders of magnitude faster than
// `/usr/bin/zipinfo` subprocess fan-out on a 600-zip corpus.

@Suite("Shared.Utils.ZipMagic header validation (#657)")
struct Issue657ZipMagicTests {
    /// Stage a file with the given byte payload in a unique temp
    /// directory and return its URL. Caller cleans up.
    private func makeFixture(named: String, bytes: [UInt8]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-zip-magic-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(named)
        try Data(bytes).write(to: url)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Happy path: each of the 3 spec-valid signatures passes

    @Test("Local file header (PK\\x03\\x04) is valid — the common case")
    func localFileHeaderValid() throws {
        let url = try makeFixture(
            named: "real.zip",
            bytes: Shared.Utils.ZipMagic.localFileHeader + [0xde, 0xad]
        )
        defer { cleanup(url) }
        #expect(Shared.Utils.ZipMagic.isValid(at: url))
    }

    @Test("End-of-central-directory signature (PK\\x05\\x06) is valid — empty archive")
    func endOfCentralDirectoryValid() throws {
        let url = try makeFixture(
            named: "empty.zip",
            bytes: Shared.Utils.ZipMagic.endOfCentralDirectory + Array(repeating: 0x00, count: 18)
        )
        defer { cleanup(url) }
        #expect(Shared.Utils.ZipMagic.isValid(at: url))
    }

    @Test("Spanned archive marker (PK\\x07\\x08) is valid — rare but spec-allowed")
    func spannedArchiveValid() throws {
        let url = try makeFixture(
            named: "spanned.zip",
            bytes: Shared.Utils.ZipMagic.spannedArchive + [0x00, 0x00]
        )
        defer { cleanup(url) }
        #expect(Shared.Utils.ZipMagic.isValid(at: url))
    }

    // MARK: - Rejection: real-world bug shapes

    @Test("HTML landing page (the #657 bug shape) is rejected")
    func htmlLandingPageRejected() throws {
        // First 4 bytes of a typical Apple developer.apple.com landing
        // page: `<!DO` (0x3C 0x21 0x44 0x4F). Not a ZIP.
        let html = "<!DOCTYPE html><html><body>Page not found</body></html>"
        let url = try makeFixture(named: "accessibility.zip", bytes: Array(html.utf8))
        defer { cleanup(url) }
        #expect(!Shared.Utils.ZipMagic.isValid(at: url))
    }

    @Test("Truncated body (1 byte) is rejected")
    func truncatedBodyRejected() throws {
        let url = try makeFixture(named: "truncated.zip", bytes: [0x50])
        defer { cleanup(url) }
        #expect(!Shared.Utils.ZipMagic.isValid(at: url))
    }

    @Test("Empty file is rejected")
    func emptyFileRejected() throws {
        let url = try makeFixture(named: "empty-body.zip", bytes: [])
        defer { cleanup(url) }
        #expect(!Shared.Utils.ZipMagic.isValid(at: url))
    }

    @Test("Random binary that doesn't start with PK is rejected")
    func randomBinaryRejected() throws {
        let url = try makeFixture(
            named: "random.zip",
            bytes: [0xff, 0xd8, 0xff, 0xe0] // JPEG magic, not ZIP
        )
        defer { cleanup(url) }
        #expect(!Shared.Utils.ZipMagic.isValid(at: url))
    }

    @Test("Almost-but-not-quite PK header is rejected")
    func almostPKRejected() throws {
        // `PK` followed by spec-disallowed bytes — would pass a naive
        // "starts with PK" check but fails the full 4-byte signature
        // comparison.
        let url = try makeFixture(
            named: "almost.zip",
            bytes: [0x50, 0x4b, 0x99, 0x99]
        )
        defer { cleanup(url) }
        #expect(!Shared.Utils.ZipMagic.isValid(at: url))
    }

    // MARK: - I/O failures

    @Test("Missing file is rejected (no crash, no permission lookup)")
    func missingFileRejected() {
        let url = URL(fileURLWithPath: "/tmp/cupertino-nonexistent-\(UUID().uuidString).zip")
        #expect(!Shared.Utils.ZipMagic.isValid(at: url))
    }
}
