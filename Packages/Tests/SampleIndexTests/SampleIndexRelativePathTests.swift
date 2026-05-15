import Foundation
@testable import SampleIndex
import SharedConstants
import Testing

// MARK: - #593 — samples indexer relative-path computation
//
// Pre-fix, `Sample.Index.Builder` computed file paths via
// `fileURL.path.replacingOccurrences(of: projectRoot.path + "/", ...)`.
// On macOS the project-root path was `/var/folders/.../tmp.XXX/` while
// the enumerator-returned file path was the symlink-resolved
// `/private/var/folders/.../tmp.XXX/Shared/foo.swift`. The substring
// strip found the prefix in the middle of the resolved path and
// removed it, leaving `/private` clinging to the front: every indexed
// file ended up as `/privateShared/foo.swift` etc. — making
// `cupertino read-sample-file <id> Shared/foo.swift` return
// "File not found" because the indexed key was actually
// `/privateShared/foo.swift`.
//
// The post-fix helper `Sample.Index.Builder.relativePath(of:under:)`
// uses URL `pathComponents` math and resolves both sides through
// symlinks first; it's robust to the macOS `/var → /private/var`
// resolution discrepancy and to any other future case where the two
// URLs disagree on prefix shape.

@Suite("Sample.Index.Builder.relativePath (#593 /private prefix bug)")
struct SampleIndexRelativePathTests {
    typealias SUT = Sample.Index.Builder

    // MARK: - Synthetic temp-dir test (exercises macOS /var → /private/var)

    @Test("temp-dir file path is computed without /private prefix corruption")
    func tempDirNoPrefixCorruption() throws {
        // Build a real project tree in $TMPDIR. On macOS, $TMPDIR
        // resolves through the /var → /private/var symlink, which is
        // exactly the case the original code mishandled. The test
        // therefore catches a regression of the original bug.
        let rawTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-relpath-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rawTempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rawTempDir) }

        // Place a Shared/foo.swift inside the project.
        let sharedDir = rawTempDir.appendingPathComponent("Shared")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let fileURL = sharedDir.appendingPathComponent("foo.swift")
        try "// fixture".write(to: fileURL, atomically: true, encoding: .utf8)

        // The caller resolves the root once outside the enumerator loop.
        let resolvedRoot = rawTempDir.resolvingSymlinksInPath()

        // Pass the file URL the enumerator would hand back. We simulate
        // the macOS-resolved form explicitly; `resolvingSymlinksInPath`
        // inside the helper handles either input form.
        let result = SUT.relativePath(of: fileURL, under: resolvedRoot)

        // Pre-fix this would have been "/privateShared/foo.swift".
        #expect(result == "Shared/foo.swift")
        #expect(!result.hasPrefix("/private"))
        #expect(!result.hasPrefix("/"))
    }

    @Test("nested directory: every segment between root and file is preserved verbatim")
    func nestedSegmentsPreserved() throws {
        let rawTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-relpath-nested-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rawTempDir) }
        let nestedDir = rawTempDir.appendingPathComponent("Shared/Model/Sub")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let fileURL = nestedDir.appendingPathComponent("Item.swift")
        try "// nested fixture".write(to: fileURL, atomically: true, encoding: .utf8)

        let resolvedRoot = rawTempDir.resolvingSymlinksInPath()
        let result = SUT.relativePath(of: fileURL, under: resolvedRoot)
        #expect(result == "Shared/Model/Sub/Item.swift")
    }

    @Test("file directly under root: returns just the file name")
    func fileAtRoot() throws {
        let rawTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-relpath-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rawTempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rawTempDir) }
        let fileURL = rawTempDir.appendingPathComponent("README.md")
        try "# fixture".write(to: fileURL, atomically: true, encoding: .utf8)

        let resolvedRoot = rawTempDir.resolvingSymlinksInPath()
        let result = SUT.relativePath(of: fileURL, under: resolvedRoot)
        // Pre-fix this would have been "/privateREADME.md".
        #expect(result == "README.md")
    }

    // MARK: - Edge cases

    @Test("file URL passed in raw (unresolved) form still produces correct relative path")
    func unresolvedFileURLIsResolvedInternally() throws {
        // FileManager.default.temporaryDirectory returns the
        // unresolved /var/folders/... path on macOS; the helper must
        // resolve it internally before comparing to the resolved root.
        let rawTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-relpath-unresolved-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rawTempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rawTempDir) }
        let sharedDir = rawTempDir.appendingPathComponent("Shared")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let fileURL = sharedDir.appendingPathComponent("Bar.swift")
        try "// unresolved-form fixture".write(to: fileURL, atomically: true, encoding: .utf8)

        // Both arguments in the unresolved form — internal resolution
        // brings them onto the same prefix.
        let result = SUT.relativePath(of: fileURL, under: rawTempDir.resolvingSymlinksInPath())
        #expect(result == "Shared/Bar.swift")
    }

    @Test("file outside root falls back to lastPathComponent (unexpected setup, sane behaviour)")
    func fileOutsideRootFallback() throws {
        let rootA = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-relpath-rootA-\(UUID().uuidString)")
        let rootB = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-relpath-rootB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let outsideFile = rootB.appendingPathComponent("orphan.swift")
        try "// orphan fixture".write(to: outsideFile, atomically: true, encoding: .utf8)

        let result = SUT.relativePath(of: outsideFile, under: rootA.resolvingSymlinksInPath())
        // Sane fallback rather than emitting a path containing the
        // absolute prefix of the unrelated root.
        #expect(result == "orphan.swift")
    }
}
