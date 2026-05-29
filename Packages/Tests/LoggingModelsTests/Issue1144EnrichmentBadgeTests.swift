import Foundation
import LoggingModels
import Testing

/// #1144: the progress-line enrichment badge is a LIVE re-check, so it flips
/// `🚫`→`🧬` the moment an operator produces a missing input mid-save (the
/// input is not read until the enrichment phase, so it is still applied).
@Suite("#1144 enrichment badge")
struct Issue1144EnrichmentBadgeTests {
    private static func tempFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("badge-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: url.path, contents: Data("{}".utf8))
        return url
    }

    private static func absentPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).json").path
    }

    @Test("no paths bound: no badge")
    func noPaths() {
        #expect(Logging.enrichmentBadge() == nil)
    }

    @Test("empty paths (DB declares no inputs): no badge")
    func emptyPaths() {
        Logging.$enrichmentInputPaths.withValue([]) {
            #expect(Logging.enrichmentBadge() == nil)
        }
    }

    @Test("all inputs present: 🧬")
    func allPresent() {
        let fileA = Self.tempFile()
        let fileB = Self.tempFile()
        defer {
            try? FileManager.default.removeItem(at: fileA)
            try? FileManager.default.removeItem(at: fileB)
        }
        Logging.$enrichmentInputPaths.withValue([fileA.path, fileB.path]) {
            #expect(Logging.enrichmentBadge() == "🧬")
        }
    }

    @Test("one input missing: 🚫 no-enrich")
    func oneMissing() {
        let present = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: present) }
        Logging.$enrichmentInputPaths.withValue([present.path, Self.absentPath()]) {
            #expect(Logging.enrichmentBadge() == "🚫 no-enrich")
        }
    }

    @Test("badge flips 🚫 -> 🧬 the moment the missing file appears (live re-check)")
    func flipsLiveWhenFileAppears() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("flip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: path) }
        Logging.$enrichmentInputPaths.withValue([path.path]) {
            #expect(Logging.enrichmentBadge() == "🚫 no-enrich")
            FileManager.default.createFile(atPath: path.path, contents: Data("{}".utf8))
            #expect(Logging.enrichmentBadge() == "🧬")
        }
    }
}
