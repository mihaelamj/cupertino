import Foundation
@testable import Resources
import Testing

// Embed-only resource access (#161). After the bundle was dropped, the only
// public surface is `CupertinoResources.jsonData(named:)` and
// `.jsonString(named:)`. These tests guard that the known names still resolve
// to non-empty, JSON-parseable payloads, and that unknown names cleanly
// return nil (no crash, no fallback).

@Suite("CupertinoResources embedded accessors (#161)")
struct CupertinoResourcesTests {
    /// sample-code-catalog removed in #215 — auto-discovery via
    /// `cupertino fetch --type code` is the source of truth for sample-code
    /// metadata, materialized at `<sample-code-dir>/catalog.json` rather
    /// than in the binary.
    private static let knownNames = [
        "priority-packages",
        "archive-guides-catalog",
    ]

    @Test("jsonData returns non-empty payload for every known catalog", arguments: knownNames)
    func jsonDataKnown(name: String) throws {
        let data = try #require(CupertinoResources.jsonData(named: name))
        #expect(!data.isEmpty)
    }

    @Test("jsonString returns non-empty payload for every known catalog", arguments: knownNames)
    func jsonStringKnown(name: String) throws {
        let str = try #require(CupertinoResources.jsonString(named: name))
        #expect(!str.isEmpty)
    }

    @Test("jsonData returns nil for unknown name")
    func jsonDataUnknown() {
        #expect(CupertinoResources.jsonData(named: "no-such-catalog") == nil)
        #expect(CupertinoResources.jsonData(named: "") == nil)
    }

    @Test("jsonString returns nil for unknown name")
    func jsonStringUnknown() {
        #expect(CupertinoResources.jsonString(named: "no-such-catalog") == nil)
        #expect(CupertinoResources.jsonString(named: "") == nil)
    }

    @Test("jsonData matches jsonString bytes for each known catalog", arguments: knownNames)
    func dataAndStringAgree(name: String) throws {
        let data = try #require(CupertinoResources.jsonData(named: name))
        let str = try #require(CupertinoResources.jsonString(named: name))
        #expect(data == Data(str.utf8))
    }

    @Test("every known catalog parses as valid JSON", arguments: knownNames)
    func parsesAsJSON(name: String) throws {
        let data = try #require(CupertinoResources.jsonData(named: name))
        let obj = try JSONSerialization.jsonObject(with: data)
        #expect(obj is [String: Any] || obj is [Any])
    }

    @Test("swift-packages-catalog is intentionally NOT exposed via jsonData")
    func swiftPackagesCatalogNotExposed() {
        // Per #161 docstring: the Swift packages catalog was slimmed to a URL
        // list and must be accessed through Core.SwiftPackagesCatalog, not
        // through the raw JSON accessor.
        #expect(CupertinoResources.jsonData(named: "swift-packages-catalog") == nil)
        #expect(CupertinoResources.jsonString(named: "swift-packages-catalog") == nil)
    }
}
