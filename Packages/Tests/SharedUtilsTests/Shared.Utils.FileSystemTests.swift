import Foundation
import SharedConstants
import Testing

// Tests for the FileSystem symlink-safe wrappers added in #786.
// Uses real temp directories and symlinks — no mocking.

@Suite("FileSystem symlink-safe wrappers")
struct FileSystemTests {
    @Test("contentsOfDirectory resolves symlink-to-directory")
    func contentsOfDirectoryFollowsSymlink() throws {
        let tmp = FileManager.default.temporaryDirectory
        let real = tmp.appendingPathComponent(UUID().uuidString)
        let link = tmp.appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "hello".write(to: real.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        defer {
            try? FileManager.default.removeItem(at: real)
            try? FileManager.default.removeItem(at: link)
        }

        let contents = try FileSystem.contentsOfDirectory(at: link, includingPropertiesForKeys: nil)
        #expect(contents.count == 1)
        #expect(contents[0].lastPathComponent == "test.txt")
    }

    @Test("enumerator returns non-nil enumerator through symlink-to-directory")
    func enumeratorFollowsSymlink() throws {
        let tmp = FileManager.default.temporaryDirectory
        let real = tmp.appendingPathComponent(UUID().uuidString)
        let link = tmp.appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        defer {
            try? FileManager.default.removeItem(at: real)
            try? FileManager.default.removeItem(at: link)
        }

        let enumerator = FileSystem.enumerator(at: link, includingPropertiesForKeys: nil)
        #expect(enumerator != nil)
    }
}
