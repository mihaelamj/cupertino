// swiftlint:disable line_length
// (descriptive STATUS comments + long path strings exceed the 120-char guideline)

@testable import CLI
import Foundation
import Testing

// MARK: - #1045 production-call-site regression test

//
// The behavioural suite (`Issue1045BehavioralWiringTests`) calls
// `CLIImpl.make<X>(...)` helpers directly and verifies their logic.
// That catches a regression where the helper logic itself breaks.
//
// It does NOT catch a regression where someone refactors a CLI command
// and drops the helper call entirely (e.g. removes
// `sourceWeightsOverride:` from the `SmartQuery.init` site). The
// behavioural test still passes because it doesn't invoke the CLI
// command — only the helper.
//
// This suite is the third layer: it reads the production CLI source
// files at test time and asserts each one contains the
// `CLIImpl.make<X>(...)` call. A refactor that drops the call breaks
// the test immediately. Ugly but mechanically reliable.
//
// Pattern mirrored from `Issue1042PluggabilityContractTests`
// Cluster 14 (which reads `Packages/Package.swift` to assert the
// `allSourceTargetDeps` helper is referenced).

@Suite("Issue #1045 — production CLI call sites invoke the registry helpers")
struct Issue1045ProductionCallSiteTests {
    /// Walk up from this source file until we find the workspace root
    /// (`cupertino/`) — the directory containing both `Packages/` and
    /// `docs/`. `#filePath` is the absolute path; #file may be
    /// relativized by SwiftPM build settings.
    private static func workspaceRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let packages = dir.appendingPathComponent("Packages")
            if FileManager.default.fileExists(atPath: packages.path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/")
    }

    private static func sourceFile(_ relativePath: String) throws -> String {
        let url = workspaceRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Gap 1 — SmartQuery weights call site

    @Test("Gap 1 — CLIImpl.Command.Search.swift invokes CLIImpl.makeSmartQuerySourceWeights")
    func gap1_searchCommandInvokesHelper() throws {
        let body = try Self.sourceFile("Packages/Sources/CLI/Commands/CLIImpl.Command.Search.swift")
        #expect(
            body.contains("CLIImpl.makeSmartQuerySourceWeights"),
            "CLIImpl.Command.Search.swift must call CLIImpl.makeSmartQuerySourceWeights so SmartQuery receives the registry-derived rankWeight dict (#1045 Gap 1)"
        )
        #expect(
            body.contains("sourceWeightsOverride:"),
            "CLIImpl.Command.Search.swift must pass the helper result as sourceWeightsOverride: to SmartQuery.init (#1045 Gap 1)"
        )
    }

    // MARK: - Gap 2 — Formatter availableSources call sites

    @Test("Gap 2 — CLI formatter call sites invoke CLIImpl.makeFormatterAvailableSources")
    func gap2_formatterCallSitesInvokeHelper() throws {
        let sourceRunners = try Self.sourceFile("Packages/Sources/CLI/Commands/CLIImpl.Command.Search.SourceRunners.swift")
        let listFrameworks = try Self.sourceFile("Packages/Sources/CLI/Commands/CLIImpl.Command.ListFrameworks.swift")
        let runnersCount = sourceRunners.components(separatedBy: "CLIImpl.makeFormatterAvailableSources").count - 1
        let listFwCount = listFrameworks.components(separatedBy: "CLIImpl.makeFormatterAvailableSources").count - 1
        // 3 paths in SourceRunners (docs / samples / HIG); 1 in ListFrameworks.
        #expect(
            runnersCount >= 3,
            "CLIImpl.Command.Search.SourceRunners.swift must call CLIImpl.makeFormatterAvailableSources at least 3 times (docs, samples, HIG paths); found \(runnersCount)"
        )
        #expect(
            listFwCount >= 1,
            "CLIImpl.Command.ListFrameworks.swift must call CLIImpl.makeFormatterAvailableSources at least once; found \(listFwCount)"
        )
    }

    // MARK: - Gap 3 — DocKind dict consumed by Classify.kind

    @Test("Gap 3 — Search.Index.IndexingDocs.swift threads sourceLookup.docKindRawValuesByID into Classify.kind")
    func gap3_indexingDocsCallSiteThreadsDocKindDict() throws {
        let body = try Self.sourceFile("Packages/Sources/SearchSQLite/Search.Index.IndexingDocs.swift")
        let count = body.components(separatedBy: "docKindByID: sourceLookup.docKindRawValuesByID").count - 1
        #expect(
            count >= 2,
            "Search.Index.IndexingDocs.swift must thread docKindByID: sourceLookup.docKindRawValuesByID into both Classify.kind call sites (#1045 Gap 3); found \(count)"
        )
    }

    // MARK: - Gap 4 — DocsIndexing directory dict at Save site

    @Test("Gap 4 — CLIImpl.Command.Save.Indexers.swift invokes CLIImpl.makeDocsIndexingDirectoryByKey")
    func gap4_saveIndexersInvokesHelper() throws {
        let body = try Self.sourceFile("Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift")
        #expect(
            body.contains("CLIImpl.makeDocsIndexingDirectoryByKey"),
            "CLIImpl.Command.Save.Indexers.swift must call CLIImpl.makeDocsIndexingDirectoryByKey so the indexer Input carries the registry-derived directory dict (#1045 Gap 4)"
        )
        #expect(
            body.contains("directoryByKey:"),
            "CLIImpl.Command.Save.Indexers.swift must pass the helper result via Indexer.DocsService.Request(directoryByKey:) (#1045 Gap 4)"
        )
    }

    // MARK: - Sanity: workspaceRoot resolution + helper file present

    @Test("Workspace root resolves + CLIImpl.SourceRegistry.swift defines all 4 helpers")
    func workspaceRootResolvesAndHelpersDefined() throws {
        let body = try Self.sourceFile("Packages/Sources/CLI/CLIImpl.SourceRegistry.swift")
        #expect(body.contains("func makeSmartQuerySourceWeights"))
        #expect(body.contains("func makeFormatterAvailableSources"))
        #expect(body.contains("func makeDocsIndexingDirectoryByKey"))
        #expect(body.contains("func makeDocKindRawValuesByID"))
    }
}
