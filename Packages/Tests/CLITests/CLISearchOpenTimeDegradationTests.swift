@testable import CLI
import Foundation
import SearchModels
import SharedConstants
import Testing

// MARK: - CLI JSON degradedSources for per-source DB open failures

//
// Main's 2026-05-16 post-#658 retest found that `cupertino search
// --format json` left `degradedSources` empty when search.db
// failed to OPEN (vs. throwing per-query). Same blind spot as #648
// (open-time) on the MCP side: when a docs fetcher never gets
// wired, no per-fetcher throw exists for `SmartQuery.answer`'s
// `classifyDegradation` plumbing to catch.
//
// `CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
//   result:disabledReasonsBySource:)` bridges the
// `FetcherPlan.disabledReasonsBySource` signal (from
// `openDocsFetchers`' classifier when an open fails) into the
// `SmartResult.degradedSources` array, mirroring
// `CompositeToolProvider.injectOpenTimeDegradation` from PR #652 on
// the MCP side.
//
// Post-#1037/#1038 the signal is a per-source dictionary (one entry
// per per-source DB that exists but couldn't open), not a single
// blanket reason -- a partial failure like `hig.db` stale while the
// rest opened cleanly now surfaces just `hig` as degraded rather
// than fabricating six fake `DegradedSource` entries.
//
// Pure function on value types -- no fetchers, no I/O, no DB. The
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

    @Test("Empty disabledReasonsBySource returns the result untouched")
    func emptyMapIsIdentity() {
        let result = makeResult()
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: result,
            disabledReasonsBySource: [:]
        )
        #expect(augmented.degradedSources.isEmpty)
        #expect(augmented.question == "anything")
        #expect(augmented.contributingSources == ["samples", "packages"])
    }

    @Test("All 6 docs sources can be reported as degraded with their own reasons")
    func allSixSourcesInjected() {
        let reason = "schema mismatch; run `cupertino setup` to redownload a matching bundle"
        let reasons: [String: String] = [
            Shared.Constants.SourcePrefix.appleDocs: reason,
            Shared.Constants.SourcePrefix.appleArchive: reason,
            Shared.Constants.SourcePrefix.hig: reason,
            Shared.Constants.SourcePrefix.swiftEvolution: reason,
            Shared.Constants.SourcePrefix.swiftOrg: reason,
            Shared.Constants.SourcePrefix.swiftBook: reason,
        ]
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(),
            disabledReasonsBySource: reasons
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
        // samples + packages live in different DBs and aren't passed
        // in here, so they stay out of the synthesised list.
        #expect(!names.contains(Shared.Constants.SourcePrefix.samples))
        #expect(!names.contains(Shared.Constants.SourcePrefix.packages))
        for degraded in augmented.degradedSources {
            #expect(degraded.reason == reason)
        }
    }

    @Test("Partial failure: only the listed source becomes degraded (post-#1037 per-source DBs)")
    func partialFailureIsScoped() {
        let reasons: [String: String] = [
            Shared.Constants.SourcePrefix.hig: "schema 18 file, builder expects 19",
        ]
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(),
            disabledReasonsBySource: reasons
        )
        #expect(augmented.degradedSources.count == 1)
        #expect(augmented.degradedSources.first?.name == Shared.Constants.SourcePrefix.hig)
        #expect(augmented.degradedSources.first?.reason == "schema 18 file, builder expects 19")
    }

    @Test("Synthesised entries are emitted in stable source-id order")
    func deterministicOrdering() {
        let reasons: [String: String] = [
            Shared.Constants.SourcePrefix.swiftBook: "r1",
            Shared.Constants.SourcePrefix.appleDocs: "r2",
            Shared.Constants.SourcePrefix.hig: "r3",
        ]
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(),
            disabledReasonsBySource: reasons
        )
        let names = augmented.degradedSources.map(\.name)
        #expect(names == [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftBook,
        ])
    }

    @Test("Existing degradedSources entries aren't duplicated; original reason preserved on collision")
    func dedupAgainstExisting() {
        let existing = [
            Search.DegradedSource(
                name: Shared.Constants.SourcePrefix.appleDocs,
                reason: "fetcher-time error preserved verbatim"
            ),
        ]
        let reasons: [String: String] = [
            Shared.Constants.SourcePrefix.appleDocs: "schema mismatch",
            Shared.Constants.SourcePrefix.hig: "schema mismatch",
        ]
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(degradedSources: existing),
            disabledReasonsBySource: reasons
        )
        // 1 existing apple-docs (untouched) + 1 synthesised hig.
        #expect(augmented.degradedSources.count == 2)
        let appleDocsEntries = augmented.degradedSources.filter {
            $0.name == Shared.Constants.SourcePrefix.appleDocs
        }
        #expect(appleDocsEntries.count == 1)
        #expect(appleDocsEntries.first?.reason == "fetcher-time error preserved verbatim")
        let higEntry = augmented.degradedSources.first { $0.name == Shared.Constants.SourcePrefix.hig }
        #expect(higEntry?.reason == "schema mismatch")
    }

    @Test("Non-degradedSources SmartResult fields pass through unchanged")
    func otherFieldsPreserved() {
        let augmented = CLIImpl.Command.Search.augmentWithOpenTimeDegradation(
            result: makeResult(),
            disabledReasonsBySource: [Shared.Constants.SourcePrefix.appleDocs: "schema mismatch"]
        )
        #expect(augmented.question == "anything")
        #expect(augmented.contributingSources == ["samples", "packages"])
        #expect(augmented.candidates.isEmpty)
    }
}
