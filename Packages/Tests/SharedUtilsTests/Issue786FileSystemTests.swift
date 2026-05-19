import Foundation
import SharedConstants
import Testing

// MARK: - #786 / Shared.Utils.FileSystem symlink-safe directory wrappers

//
// Background: `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`
// and `FileManager.enumerator(at:includingPropertiesForKeys:options:)`, the
// URL-taking variants of these APIs, do NOT follow a directory-symlink at the
// leaf URL. They operate on the symlink inode itself; the kernel returns
// `ENOTDIR` (POSIX errno 20); Foundation wraps as `NSCocoaErrorDomain` code 256
// (`NSFileReadUnknownError`) with the bare `localizedDescription` `"The file
// \"X\" couldn't be opened."` (no `because…` suffix). This was the root cause
// of #779, which crashed `cupertino save` at the 11h mark when SwiftEvolution's
// optional source dir was a symlink in the dev layout.
//
// The `Shared.Utils.FileSystem` wrappers pre-resolve the URL via
// `URL.resolvingSymlinksInPath()` and delegate to the raw API. The String-
// variant siblings (`contentsOfDirectory(atPath:)`) and `FileManager.fileExists`
// both follow symlinks correctly, so this is a divergence only the URL variant
// suffers from.

@Suite("Shared.Utils.FileSystem symlink-safe wrappers (#786)")
struct Issue786FileSystemTests {
    /// Stage a real directory with two files inside, plus a symlink that points at it.
    /// Returns (realDir, symlink, tmpRoot). Caller cleans up via tmpRoot.
    private func makeSymlinkFixture() throws -> (realDir: URL, symlink: URL, tmpRoot: URL) {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-fs-symlink-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        let realDir = tmpRoot.appendingPathComponent("real-target-dir")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: realDir.appendingPathComponent("file1.txt"))
        try Data("two".utf8).write(to: realDir.appendingPathComponent("file2.txt"))

        let symlink = tmpRoot.appendingPathComponent("symlink-to-real-target")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realDir)

        return (realDir, symlink, tmpRoot)
    }

    private func cleanup(_ tmpRoot: URL) {
        try? FileManager.default.removeItem(at: tmpRoot)
    }

    // MARK: - Raw FileManager URL-variant API on a leaf directory-symlink throws ENOTDIR

    @Test("Raw FileManager.contentsOfDirectory(at:) on a leaf dir-symlink throws ENOTDIR")
    func rawAPIThrowsOnSymlink() throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture.tmpRoot) }

        // The bug we are wrapping. fileExists says yes; the URL-variant directory
        // enumeration says no, "Not a directory". This asserts the documented divergence.
        #expect(FileManager.default.fileExists(atPath: fixture.symlink.path))

        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: fixture.symlink,
                includingPropertiesForKeys: nil
            )
            Issue.record("expected raw API to throw on the symlink leaf, but it did not")
        } catch {
            let ns = error as NSError
            #expect(ns.domain == NSCocoaErrorDomain)
            #expect(ns.code == 256)
            let inner = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            #expect(inner?.domain == NSPOSIXErrorDomain)
            #expect(inner?.code == 20) // ENOTDIR
        }
    }

    // MARK: - Wrapper contentsOfDirectory succeeds on a leaf dir-symlink (the fix)

    @Test("Wrapper contentsOfDirectory follows leaf dir-symlinks")
    func wrapperContentsOfDirectoryFollowsSymlink() throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture.tmpRoot) }

        let entries = try Shared.Utils.FileSystem.contentsOfDirectory(
            at: fixture.symlink,
            includingPropertiesForKeys: nil
        )

        let names = Set(entries.map(\.lastPathComponent))
        #expect(names == Set(["file1.txt", "file2.txt"]))
    }

    // MARK: - Wrapper contentsOfDirectory is a no-op on real (non-symlink) URLs

    @Test("Wrapper contentsOfDirectory is a no-op on a real (non-symlink) directory URL")
    func wrapperContentsOfDirectoryNoOpOnRealDir() throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture.tmpRoot) }

        let entries = try Shared.Utils.FileSystem.contentsOfDirectory(
            at: fixture.realDir,
            includingPropertiesForKeys: nil
        )

        let names = Set(entries.map(\.lastPathComponent))
        #expect(names == Set(["file1.txt", "file2.txt"]))
    }

    // MARK: - Wrapper enumerator follows leaf dir-symlinks

    @Test("Wrapper enumerator follows leaf dir-symlinks")
    func wrapperEnumeratorFollowsSymlink() throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture.tmpRoot) }

        guard let enumerator = Shared.Utils.FileSystem.enumerator(
            at: fixture.symlink,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("expected an enumerator, got nil")
            return
        }

        var names = Set<String>()
        while let next = enumerator.nextObject() as? URL {
            names.insert(next.lastPathComponent)
        }
        #expect(names == Set(["file1.txt", "file2.txt"]))
    }

    // MARK: - Wrapper enumerator is a no-op on real (non-symlink) URLs

    @Test("Wrapper enumerator is a no-op on a real (non-symlink) directory URL")
    func wrapperEnumeratorNoOpOnRealDir() throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture.tmpRoot) }

        guard let enumerator = Shared.Utils.FileSystem.enumerator(
            at: fixture.realDir,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("expected an enumerator on a real dir, got nil")
            return
        }

        var names = Set<String>()
        while let next = enumerator.nextObject() as? URL {
            names.insert(next.lastPathComponent)
        }
        #expect(names == Set(["file1.txt", "file2.txt"]))
    }
}
