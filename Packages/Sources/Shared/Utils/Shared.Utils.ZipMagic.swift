import Foundation

extension Shared.Utils {
    /// #657 — quick header validation for ZIP archives downloaded by
    /// `cupertino fetch --type samples`. Apple's CDN sometimes returns
    /// an HTML landing page or a partial body with HTTP 200 (transient
    /// CDN issues, redirect chains, auth gates) and the fetcher saves
    /// the body to disk with a `.zip` extension. Pre-#657 those entries
    /// lingered in `~/.cupertino/sample-code/` until `cupertino save
    /// --samples` hit them at index time — main's 2026-05-16
    /// post-#653 retest found 3 such corruptions on the live corpus
    /// (`accessibility.zip`, `appintents.zip`,
    /// `ios-ipados-release-notes.zip`).
    ///
    /// The validator reads the first 4 bytes of the file and checks
    /// for one of the three ZIP signature prefixes from the PKWARE
    /// APPNOTE.TXT (sections 4.3.7, 4.3.16, 4.4.5):
    ///
    ///   - `0x50 0x4B 0x03 0x04` (`PK\x03\x04`) — local file header,
    ///     the common case for any archive containing at least one
    ///     entry.
    ///   - `0x50 0x4B 0x05 0x06` (`PK\x05\x06`) — end of central
    ///     directory record only, the legitimate shape of an empty
    ///     ZIP archive (zero entries).
    ///   - `0x50 0x4B 0x07 0x08` (`PK\x07\x08`) — spanned archive
    ///     marker; rare in practice but spec-valid.
    ///
    /// 4 bytes of I/O per file is roughly 3 orders of magnitude faster
    /// than the `zipinfo` subprocess fan-out that `cleanup --dry-run
    /// --verify` uses for a more thorough scan; it doesn't detect
    /// truncated archives whose header survived, so callers needing
    /// integrity (vs. format) should still reach for `zipinfo`. For
    /// the fetch-time + doctor-probe surfaces this PR covers, "is
    /// this even a ZIP?" is the right question.
    public enum ZipMagic {
        /// Local file header signature — the common case for any
        /// archive containing at least one entry. PKWARE APPNOTE
        /// section 4.3.7.
        public static let localFileHeader: [UInt8] = [0x50, 0x4b, 0x03, 0x04]

        /// End of central directory record signature — legitimate
        /// for empty archives (zero entries). PKWARE APPNOTE section
        /// 4.3.16.
        public static let endOfCentralDirectory: [UInt8] = [0x50, 0x4b, 0x05, 0x06]

        /// Spanned archive marker. PKWARE APPNOTE section 4.4.5.
        public static let spannedArchive: [UInt8] = [0x50, 0x4b, 0x07, 0x08]

        /// Returns `true` when the file at `url` opens cleanly AND the
        /// first 4 bytes match one of the three ZIP magic signatures.
        /// Returns `false` for missing files, permission denied,
        /// truncated reads (<4 bytes), and any other I/O failure.
        public static func isValid(at url: URL) -> Bool {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return false
            }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 4), data.count == 4 else {
                return false
            }
            let bytes = Array(data)
            return bytes == localFileHeader
                || bytes == endOfCentralDirectory
                || bytes == spannedArchive
        }
    }
}
