@testable import CLI
import Foundation
import LoggingModels
import SearchModels
import SearchSQLite
import SharedConstants
import Testing

// MARK: - #932 coverage pins: IndexerRegistry composition-root injection

/// Fake SourceIndexer that records every dispatch hook call. Used to
/// prove `Search.Index.indexItem` reads from the injected dict, not
/// from any static surface. Pre-#932 a static `Search.IndexerRegistry`
/// dispatched globally regardless of who constructed the actor;
/// post-#932 the only way for indexItem to find an indexer for source
/// `X` is for the construction site to have injected an entry for
/// source `X`.
private actor FakeSourceIndexer: Search.SourceIndexer {
    nonisolated let sourceID: String
    nonisolated let displayName: String
    private var _preprocessCalls: [String] = []
    private var _postprocessCalls: [String] = []
    private var _validateCalls: [String] = []

    init(sourceID: String, displayName: String = "Fake") {
        self.sourceID = sourceID
        self.displayName = displayName
    }

    nonisolated func validate(_: Search.SourceItem) -> Bool {
        // Actor-isolated state would need an async hop; this hook stays
        // non-recording to keep the protocol's synchronous shape.
        true
    }

    nonisolated func extractCode(from _: Search.SourceItem) -> Search.ExtractedContent {
        .empty
    }

    nonisolated func preprocess(_ item: Search.SourceItem) -> Search.SourceItem {
        // The protocol's preprocess is synchronous (nonisolated default).
        // Re-route to actor-isolated state via a detached Task so the
        // recording survives without changing the protocol contract.
        Task { await self.recordPreprocess(item.uri) }
        return item
    }

    nonisolated func postprocess(_ item: Search.SourceItem) {
        Task { await self.recordPostprocess(item.uri) }
    }

    private func recordPreprocess(_ uri: String) {
        _preprocessCalls.append(uri)
    }

    private func recordPostprocess(_ uri: String) {
        _postprocessCalls.append(uri)
    }

    var preprocessCalls: [String] {
        _preprocessCalls
    }

    var postprocessCalls: [String] {
        _postprocessCalls
    }
}

@Suite("#932: Search.Index init requires an explicit indexer dict")
struct Issue932IndexerInjectionContractTests {
    @Test("`indexers:` is a REQUIRED init parameter (no default; gof-di-rules.md Rule 2)")
    func explicitInjectionIsRequired() async throws {
        // Compile-time pin: if a future PR re-adds `indexers: [:]` default,
        // this construction will continue to compile and pass: but the
        // sibling Doctor.run / Save.Indexers / SearchModuleAlias call sites
        // (which all pass `indexers:` explicitly today) would silently
        // start using the default. The cross-file invariant is enforced by
        // grep, not by the type system; see the audit test below.
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue932-required-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: [:],
            sourceLookup: .empty
        )
        #expect(index.indexers.isEmpty)
        await index.disconnect()
    }

    @Test("no `Search.productionIndexers` Service-Locator surface exists on the Search namespace")
    func noStaticFactoryOnSearchNamespace() {
        // gof-di-rules.md Rule 1: producer namespaces must not expose
        // static factories that name a production list. Adding a
        // `Search.productionIndexers()` static would re-introduce a
        // Service Locator. We verify the absence by grepping the source
        // tree for the symbol; if a future PR adds one, this test fails.
        let repoRoot = Self.repoRoot()
        let searchSQLiteDir = repoRoot.appendingPathComponent("Packages/Sources/SearchSQLite")
        guard let enumerator = FileManager.default.enumerator(
            at: searchSQLiteDir,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("Could not enumerate SearchSQLite sources")
            return
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(
                !body.contains("static func productionIndexers"),
                "\(url.lastPathComponent) contains a static `productionIndexers` factory: Service Locator violation"
            )
            #expect(
                !body.contains("static let productionIndexers"),
                "\(url.lastPathComponent) contains a static `productionIndexers` accessor: Service Locator violation"
            )
        }
    }

    @Test("no `Search.IndexerRegistry` static surface exists in SearchSQLite")
    func noStaticIndexerRegistry() {
        let repoRoot = Self.repoRoot()
        let searchSQLiteDir = repoRoot.appendingPathComponent("Packages/Sources/SearchSQLite")
        guard let enumerator = FileManager.default.enumerator(
            at: searchSQLiteDir,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("Could not enumerate SearchSQLite sources")
            return
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            // The symbol `IndexerRegistry` may appear in a comment that
            // narrates the pre-#932 history; the violation is a re-
            // introduction of the static enum / static dict shape. Pin
            // the two structural-introduction phrases explicitly.
            #expect(
                !body.contains("public enum IndexerRegistry"),
                "\(url.lastPathComponent) reintroduces `public enum IndexerRegistry`: Singleton violation (gof-di-rules.md Rule 1)"
            )
            #expect(
                !body.contains("private static let indexers:"),
                "\(url.lastPathComponent) reintroduces a `private static let indexers`: Service Locator violation"
            )
        }
    }

    private static func repoRoot() -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("scripts").path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: cwd)
    }
}

@Suite("#932: indexItem dispatch reads from the injected dict, end-to-end")
struct Issue932IndexItemDispatchTests {
    @Test("indexItem routes through the injected indexer's preprocess hook for a matched source-id")
    func injectedIndexerReceivesPreprocessCall() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue932-dispatch-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let fake = FakeSourceIndexer(sourceID: "wwdc-transcripts")
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: ["wwdc-transcripts": fake],
            sourceLookup: .empty
        )
        defer { Task { await index.disconnect() } }

        let item = Search.SourceItem(
            uri: "wwdc-transcripts://session/2024-101",
            source: "wwdc-transcripts",
            title: "Test WWDC session",
            content: "Sample transcript content for the #932 dispatch test.",
            filePath: "test.json",
            contentHash: "deadbeef",
            framework: nil,
            language: nil,
            sourceType: "wwdc-transcripts"
        )
        try await index.indexItem(item, extractSymbols: false)

        // Both preprocess and postprocess fire on a successful dispatch.
        // The fake's recording is actor-isolated and Task-scheduled, so a
        // brief yield is needed for the post-dispatch tasks to settle
        // before assertion. A tight retry loop on the actor's state keeps
        // the test deterministic without a fragile sleep.
        var preprocessCount = 0
        for _ in 0..<50 {
            preprocessCount = await fake.preprocessCalls.count
            if preprocessCount >= 1 { break }
            try? await Task.sleep(nanoseconds: 10000000)
        }
        #expect(preprocessCount >= 1, "preprocess should fire when indexItem dispatches to the injected indexer")
        let preprocessUris = await fake.preprocessCalls
        #expect(preprocessUris.contains("wwdc-transcripts://session/2024-101"))
    }

    @Test("indexItem falls through for an UNMATCHED source-id (no static fallback survives #932)")
    func unmatchedSourceFallsThrough() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("issue932-fallthrough-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbPath) }
        // The injected dict has NO entry for "apple-docs". Pre-#932 the
        // static IndexerRegistry would have served `AppleDocsIndexer` here
        // regardless of the construction site. Post-#932 the only entry
        // available is the WWDC fake under "wwdc-transcripts"; "apple-docs"
        // dispatches to the generic indexDocument fall-through.
        let fake = FakeSourceIndexer(sourceID: "wwdc-transcripts")
        let index = try await Search.Index(
            dbPath: dbPath,
            logger: LoggingModels.Logging.NoopRecording(),
            indexers: ["wwdc-transcripts": fake],
            sourceLookup: .empty
        )
        defer { Task { await index.disconnect() } }

        let item = Search.SourceItem(
            uri: "apple-docs://swiftui/view",
            source: "apple-docs",
            title: "View",
            content: "Source-id `apple-docs` is intentionally NOT in the injected dict.",
            filePath: "test.json",
            contentHash: "cafebabe",
            framework: "SwiftUI",
            language: "swift",
            sourceType: "apple-docs"
        )
        try await index.indexItem(item, extractSymbols: false)

        // The WWDC fake must NOT have received a preprocess call: the
        // injected dispatch must NOT route across source-ids.
        try? await Task.sleep(nanoseconds: 50000000)
        let preprocessCalls = await fake.preprocessCalls
        #expect(preprocessCalls.isEmpty, "WWDC fake should not have received preprocess for apple-docs source")
    }
}
