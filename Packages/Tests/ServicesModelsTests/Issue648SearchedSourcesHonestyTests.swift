import Foundation
import SampleIndexModels
import SearchModels
import ServicesModels
import SharedConstants
import Testing

// MARK: - #648 — MCP `search` "Searched ALL sources" line is honest

//
// Pre-#642, the MCP markdown search response had no signal that some
// sources had silently failed. #642 prepended a "⚠ N sources unavailable"
// blockquote when `degradedSources` was non-empty, but the immediately
// following line still emitted
//   `_Searched ALL sources: apple-docs, samples, hig, …_`
// unconditionally. AI agents saw two contradictory signals one paragraph
// apart: the warning at the top + the "ALL" claim below.
//
// Post-#648, the line flips to the actually-searched set when
// `degradedSources` is non-empty (matching CLI's `Searched: <list>`
// output via `Search.SmartReport`). Happy path is unchanged so existing
// clients that key off the literal "Searched ALL sources" string don't
// have to special-case anything when running against an unaffected
// server.

@Suite("Services.Formatter.Unified.Markdown searched-sources honesty (#648)")
struct Issue648SearchedSourcesHonestyTests {
    private func makeInput(degradedSources: [Search.DegradedSource] = []) -> Services.Formatter.Unified.Input {
        Services.Formatter.Unified.Input(
            docResults: [],
            archiveResults: [],
            sampleResults: [],
            higResults: [],
            swiftEvolutionResults: [],
            swiftOrgResults: [],
            swiftBookResults: [],
            packagesResults: [],
            limit: 20,
            degradedSources: degradedSources
        )
    }

    private func render(_ degradedSources: [Search.DegradedSource]) -> String {
        let formatter = Services.Formatter.Unified.Markdown(query: "anything")
        return formatter.format(makeInput(degradedSources: degradedSources))
    }

    @Test("Happy path keeps the pre-#648 'Searched ALL sources' wording verbatim")
    func happyPathUnchanged() {
        let output = render([])
        #expect(output.contains("_Searched ALL sources:"))
        // The full list of sources from SharedConstants should appear.
        for source in Shared.Constants.Search.availableSources {
            #expect(output.contains(source))
        }
        // The honest-list wording must NOT appear on the happy path —
        // existing clients keying off the literal "ALL sources" string
        // would silently swap if we changed the wording unconditionally.
        #expect(!output.contains("_Searched: "))
    }

    @Test("Single degraded source flips the line to the actually-searched list")
    func singleDegradedSourceFlipsLine() {
        let appleDocs = Shared.Constants.SourcePrefix.appleDocs
        let output = render([
            Search.DegradedSource(name: appleDocs, reason: "schema mismatch"),
        ])
        // The "ALL sources" claim must not appear when any source has degraded.
        #expect(!output.contains("_Searched ALL sources"))
        // The honest list must appear and must NOT contain the degraded source.
        #expect(output.contains("_Searched: "))
        let searchedLine = output
            .split(separator: "\n")
            .first(where: { $0.contains("_Searched: ") }) ?? ""
        #expect(!searchedLine.contains(appleDocs))
        // The remaining sources must still appear in the honest list.
        for source in Shared.Constants.Search.availableSources where source != appleDocs {
            #expect(searchedLine.contains(source))
        }
    }

    @Test("Multiple degraded sources are all excluded from the honest list")
    func multipleDegradedSourcesExcluded() {
        let degraded = [
            Shared.Constants.SourcePrefix.appleDocs,
            Shared.Constants.SourcePrefix.hig,
            Shared.Constants.SourcePrefix.swiftEvolution,
        ]
        let output = render(degraded.map { Search.DegradedSource(name: $0, reason: "schema mismatch") })
        #expect(!output.contains("_Searched ALL sources"))
        let searchedLine = output
            .split(separator: "\n")
            .first(where: { $0.contains("_Searched: ") }) ?? ""
        for source in degraded {
            #expect(!searchedLine.contains(source))
        }
        // At least one healthy source should still appear (samples / packages).
        #expect(searchedLine.contains(Shared.Constants.SourcePrefix.samples)
            || searchedLine.contains(Shared.Constants.SourcePrefix.packages))
    }

    @Test("All sources degraded renders the literal '(none)' placeholder, not the ALL claim")
    func allSourcesDegraded() {
        let degraded = Shared.Constants.Search.availableSources.map {
            Search.DegradedSource(name: $0, reason: "schema mismatch")
        }
        let output = render(degraded)
        #expect(!output.contains("_Searched ALL sources"))
        #expect(output.contains("_Searched: (none)_"))
    }

    @Test("Honest-list line coexists with the prepended degradation warning (no regression on #642)")
    func warningStaysOnTop() {
        let output = render([
            Search.DegradedSource(name: Shared.Constants.SourcePrefix.appleDocs, reason: "schema mismatch"),
        ])
        // #642's prepended warning blockquote.
        #expect(output.contains("⚠"))
        #expect(output.contains("unavailable due to configuration error"))
        // The new honest-searched line must appear AFTER the warning.
        let warningRange = output.range(of: "unavailable due to configuration error")
        let searchedRange = output.range(of: "_Searched: ")
        #expect(warningRange != nil)
        #expect(searchedRange != nil)
        if let warning = warningRange, let searched = searchedRange {
            #expect(warning.lowerBound < searched.lowerBound)
        }
    }
}
