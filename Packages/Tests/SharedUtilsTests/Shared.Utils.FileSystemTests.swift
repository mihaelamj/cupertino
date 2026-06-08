import Foundation
import SharedConstants
import Testing

@Suite("Shared.Utils.FileSystem")
struct FileSystemTests {
    // MARK: - contentsOfDirectory

    @Test("contentsOfDirectory follows leaf symlink to directory")
    func contentsOfDirectoryFollowsSymlink() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let real = tmp.appendingPathComponent("real", isDirectory: true)
        let link = tmp.appendingPathComponent("link", isDirectory: true)

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sentinel = real.appendingPathComponent("file.txt")
        try "hello".write(to: sentinel, atomically: true, encoding: .utf8)

        let contents = try Shared.Utils.FileSystem.contentsOfDirectory(
            at: link,
            includingPropertiesForKeys: nil
        )
        #expect(contents.map(\.lastPathComponent).contains("file.txt"))
    }

    @Test("contentsOfDirectory on canonical path is a no-op (returns correct results)")
    func contentsOfDirectoryCanonicalPath() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sentinel = tmp.appendingPathComponent("probe.txt")
        try "data".write(to: sentinel, atomically: true, encoding: .utf8)

        let contents = try Shared.Utils.FileSystem.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil
        )
        #expect(contents.map(\.lastPathComponent).contains("probe.txt"))
    }

    // MARK: - enumerator

    @Test("enumerator follows leaf symlink to directory")
    func enumeratorFollowsSymlink() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let real = tmp.appendingPathComponent("real", isDirectory: true)
        let link = tmp.appendingPathComponent("link", isDirectory: true)

        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sentinel = real.appendingPathComponent("nested.txt")
        try "content".write(to: sentinel, atomically: true, encoding: .utf8)

        let enumerator = Shared.Utils.FileSystem.enumerator(at: link, includingPropertiesForKeys: nil)
        #expect(enumerator != nil)

        var found = false
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "nested.txt" { found = true }
        }
        #expect(found)
    }

    @Test("enumerator on canonical path is non-nil")
    func enumeratorCanonicalPath() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let enumerator = Shared.Utils.FileSystem.enumerator(at: tmp, includingPropertiesForKeys: nil)
        #expect(enumerator != nil)
    }
}
