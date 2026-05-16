import Foundation
import MCPCore
import SearchModels
@testable import SearchToolProvider
import ServicesModels
import SharedConstants
import Testing

// MARK: - #648 (open-time path) — synthetic DegradedSource injection

//
// Main's 2026-05-16 post-promote retest found that #642's per-fetcher
// `classifyDegradation` plumbing doesn't catch the case where
// `search.db` fails to open at server startup. When `searchIndex` is
// nil (because the file is unopenable, schema-mismatched, etc.), the
// `Services.UnifiedSearchService.searchAll` path is wired with
// `searchIndex: nil`; the apple-docs / hig / swift-evolution / apple-
// archive / swift-org / swift-book fetchers register as unavailable
// and are never called for the query. No per-fetcher throw exists to
// classify, so `degradedSources` stays empty + the Markdown renderer
// claims `_Searched ALL sources_` while in fact only samples + packages
// ran.
//
// PR #649 already classified the open-time failure into a
// `searchIndexDisabledReason` string on the provider. This PR bridges
// that signal into the formatter input: `injectOpenTimeDegradation(_,
// disabledReason:)` synthesises one `Search.DegradedSource` per
// search.db-backed source when a reason is set, so the existing #642
// warning blockquote + #648 (residual) `_Searched: <list>_` honest
// line both trigger for the open-time path with no formatter changes.

@Suite("#648 open-time degradation injection")
struct Issue648OpenTimeDegradationTests {
    private func makeInput(
        docResults: [Search.Result] = [],
        sampleResults: [Sample.Index.Project] = [],
        existingDegraded: [Search.DegradedSource] = []
    ) -> Services.Formatter.Unified.Input {
        Services.Formatter.Unified.Input(
            docResults: docResults,
            archiveResults: [],
            sampleResults: sampleResults,
            higResults: [],
            swiftEvolutionResults: [],
            swiftOrgResults: [],
            swiftBookResults: [],
            packagesResults: [],
            limit: 20,
            degradedSources: existingDegraded
        )
    }

    // MARK: Happy path

    @Test("nil disabledReason returns the input untouched")
    func nilReasonIsIdentity() {
        let input = makeInput()
        let result = CompositeToolProvider.injectOpenTimeDegradation(
            into: input,
            disabledReason: nil
        )
        #expect(result.degradedSources.isEmpty)
        // Identity over the result arrays too.
        #expect(result.docResults.isEmpty)
        #expect(result.archiveResults.isEmpty)
        #expect(result.sampleResults.isEmpty)
    }

    // MARK: Open-time injection

    @Test("Non-nil disabledReason synthesises 6 degraded sources (search.db-backed only)")
    func sixSourcesInjected() {
        let input = makeInput()
        let reason = "schema mismatch; run `cupertino setup` to redownload a matching bundle"
        let result = CompositeToolProvider.injectOpenTimeDegradation(
            into: input,
            disabledReason: reason
        )
        #expect(result.degradedSources.count == 6)
        let names = Set(result.degradedSources.map(\.name))
        #expect(names == Set([
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ]))
        // samples + packages live in different DBs and must NOT be in
        // the synthesised list — they continue to work when search.db
        // is the only thing broken.
        #expect(!names.contains(Shared.Constants.SourcePrefix.samples))
        #expect(!names.contains(Shared.Constants.SourcePrefix.packages))
    }

    @Test("Every synthesised entry carries the same disabledReason string")
    func reasonPropagated() {
        let reason = "database unopenable; check the `--search-db` path"
        let result = CompositeToolProvider.injectOpenTimeDegradation(
            into: makeInput(),
            disabledReason: reason
        )
        for degraded in result.degradedSources {
            #expect(degraded.reason == reason)
        }
    }

    // MARK: Dedup against existing entries

    @Test("Existing degradedSources entries aren't duplicated by the synthetic merge")
    func dedupAgainstExisting() {
        let existing = [
            Search.DegradedSource(
                name: Shared.Constants.SourcePrefix.appleDocs,
                reason: "fetcher-time error"
            ),
        ]
        let result = CompositeToolProvider.injectOpenTimeDegradation(
            into: makeInput(existingDegraded: existing),
            disabledReason: "schema mismatch"
        )
        // 6 search.db-backed sources, minus 1 already present = 5 new
        // + the existing 1 = 6 total. The existing entry's reason is
        // preserved (the per-fetcher classifier saw it first).
        #expect(result.degradedSources.count == 6)
        let appleDocsEntries = result.degradedSources.filter {
            $0.name == Shared.Constants.SourcePrefix.appleDocs
        }
        #expect(appleDocsEntries.count == 1)
        #expect(appleDocsEntries.first?.reason == "fetcher-time error")
    }

    // MARK: Preservation of non-degradedSources fields

    @Test("Non-degradedSources Input fields pass through unchanged")
    func otherFieldsPreserved() {
        // Synthesise a sample project so the sampleResults array is
        // non-empty; pinning that the helper doesn't accidentally drop
        // result arrays during the rebuild.
        let project = Sample.Index.Project(
            id: "test-sample",
            title: "Test",
            description: "Pinned by test",
            frameworks: ["SwiftUI"],
            readme: "",
            webURL: "https://example.com",
            zipFilename: "test.zip",
            fileCount: 1,
            totalSize: 100
        )
        let input = makeInput(sampleResults: [project])
        let result = CompositeToolProvider.injectOpenTimeDegradation(
            into: input,
            disabledReason: "schema mismatch"
        )
        #expect(result.sampleResults.count == 1)
        #expect(result.sampleResults.first?.id == "test-sample")
        #expect(result.limit == 20)
    }

    // MARK: Integration — full Markdown render with synthesised degraded sources

    @Test("Markdown render shows the warning + honest 'Searched:' line when reason is set")
    func endToEndMarkdownRenderTriggersBothSignals() {
        let input = CompositeToolProvider.injectOpenTimeDegradation(
            into: makeInput(),
            disabledReason: "schema mismatch; run `cupertino setup` to redownload a matching bundle"
        )
        let formatter = Services.Formatter.Unified.Markdown(query: "SwiftUI")
        let output = formatter.format(input)

        // The #642 warning blockquote must appear (6 sources unavailable).
        #expect(output.contains("⚠"))
        #expect(output.contains("6 sources unavailable due to configuration error"))
        // The #648 (residual) honest "Searched:" line must appear and
        // must NOT claim "ALL sources".
        #expect(output.contains("_Searched: "))
        #expect(!output.contains("_Searched ALL sources"))
        // Samples + packages should still be listed as searched
        // (different DBs, not affected).
        let searchedLine = output
            .split(separator: "\n")
            .first(where: { $0.contains("_Searched: ") }) ?? ""
        #expect(searchedLine.contains(Shared.Constants.SourcePrefix.samples))
        #expect(searchedLine.contains(Shared.Constants.SourcePrefix.packages))
        // None of the 6 search.db-backed sources should appear in the
        // searched line.
        for source in [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ] {
            #expect(!searchedLine.contains(source))
        }
    }
}
