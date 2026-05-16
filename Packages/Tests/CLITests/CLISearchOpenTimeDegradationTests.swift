@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - CLI JSON degradedSources for search.db open failures

//
// Main's 2026-05-16 post-#658 retest found that `cupertino search
// --format json` left `degradedSources` empty even when search.db
// failed to OPEN (vs. throwing per-query). Same blind spot as #648
// (open-time) on the MCP side — when no apple-docs fetcher gets
// wired, no per-fetcher throw exists for `SmartQuery.answer`'s
// `classifyDegradation` plumbing to catch.
//
// `CLIImpl.Command.Search.augmentWithOpenTimeDegradation(result:disabledReason:)`
// bridges the `FetcherPlan.searchDBDisabledReason` signal (from
// `openDocsFetchers`' classifier when the open fails) into the
// `SmartResult.degradedSources` array, mirroring
// `CompositeToolProvider.injectOpenTimeDegradation` from PR #652 on
// the MCP side.
//
// Pure function on value types — no fetchers, no I/O, no DB. The
// test exercises the merge logic directly.

@Suite("CLI Search open-time degradation injection")
struct CLISearchOpenTimeDegradationTests {
    private func makeResult(degradedSources: [Search.DegradedSource] = []) -> Search.SmartResult {
        Search.SmartResult(
            question: "anything",
            candidates: [],
            contributingSources: ["samples", "packages"],
            degradedSources: degradedSources
        )
    }

    @Test("nil disabledReason returns the result untouched")
    func nilReasonIsIdentity() {
        let result = makeResult()
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: result,
            disabledReason: nil
        )
        #expect(augmented.degradedSources.isEmpty)
        #expect(augmented.question == "anything")
        #expect(augmented.contributingSources == ["samples", "packages"])
    }

    @Test("Non-nil disabledReason synthesises 6 search.db-backed degraded sources")
    func sixSourcesInjected() {
        let reason = "schema mismatch; run `cupertino setup` to redownload a matching bundle"
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(),
            disabledReason: reason
        )
        #expect(augmented.degradedSources.count == 6)
        let names = Set(augmented.degradedSources.map(\.name))
        #expect(names == Set([
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.appleArchive,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
            Shared.Constants.SourcePrefix.swiftOrg,
            Shared.Constants.SourcePrefix.swiftBook,
        ]))
        // samples + packages live in different DBs and stay out of
        // the synthesised list.
        #expect(!names.contains(Shared.Constants.SourcePrefix.samples))
        #expect(!names.contains(Shared.Constants.SourcePrefix.packages))
        for degraded in augmented.degradedSources {
            #expect(degraded.reason == reason)
        }
    }

    @Test("Existing degradedSources entries aren't duplicated; original reason preserved on collision")
    func dedupAgainstExisting() {
        let existing = [
            Search.DegradedSource(
                name: Shared.Constants.SourcePrefix.appleDocs,
                reason: "fetcher-time error preserved verbatim"
            ),
        ]
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(degradedSources: existing),
            disabledReason: "schema mismatch"
        )
        #expect(augmented.degradedSources.count == 6)
        let appleDocsEntries = augmented.degradedSources.filter {
            $0.name == Shared.Constants.SourcePrefix.appleDocs
        }
        #expect(appleDocsEntries.count == 1)
        #expect(appleDocsEntries.first?.reason == "fetcher-time error preserved verbatim")
    }

    @Test("Non-degradedSources SmartResult fields pass through unchanged")
    func otherFieldsPreserved() {
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(),
            disabledReason: "schema mismatch"
        )
        #expect(augmented.question == "anything")
        #expect(augmented.contributingSources == ["samples", "packages"])
        #expect(augmented.candidates.isEmpty)
    }
}
