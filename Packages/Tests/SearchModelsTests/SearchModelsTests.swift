import Foundation
@testable import SearchModels
import Testing

// MARK: - SearchModels Public API Smoke Tests

// SearchModels owns the value types that flow through search-result
// rendering. The Search target produces values of these types; every
// downstream consumer (Services formatters, MCP responders, CLI
// rendering) decodes + renders them without taking a behavioural
// dep on Search.
//
// Per #402a / #402 / #381 acceptance: SearchModels imports only
// Foundation + SharedConstants + SharedCore + SharedModels.
// `grep -rln "^import " Packages/Sources/SearchModels/` returns
// exactly those four.

@Suite("SearchModels public surface")
struct SearchModelsPublicSurfaceTests {
    // MARK: Namespace

    @Test("Search namespace reachable from SearchModels")
    func searchNamespaceReachable() {
        _ = Search.self
    }

    // MARK: PlatformAvailability

    @Test("Search.PlatformAvailability round-trips its inputs")
    func platformAvailabilityRoundTrip() {
        let availability = Search.PlatformAvailability(
            name: "iOS",
            introducedAt: "15.0",
            deprecated: false,
            unavailable: false,
            beta: false,
        )
        #expect(availability.name == "iOS")
        #expect(availability.introducedAt == "15.0")
        #expect(availability.deprecated == false)
        #expect(availability.unavailable == false)
        #expect(availability.beta == false)
    }

    @Test("Search.PlatformAvailability decodes from canonical JSON")
    func platformAvailabilityDecodes() throws {
        let json = """
        {"name": "macOS", "introducedAt": "12.0", "deprecated": false, "unavailable": false, "beta": true}
        """.data(using: .utf8)!
        let availability = try JSONDecoder().decode(Search.PlatformAvailability.self, from: json)
        #expect(availability.name == "macOS")
        #expect(availability.introducedAt == "12.0")
        #expect(availability.beta == true)
    }

    // MARK: MatchedSymbol

    @Test("Search.MatchedSymbol displayString uses signature when present")
    func matchedSymbolDisplayWithSignature() {
        let symbol = Search.MatchedSymbol(
            kind: "func",
            name: "scaledFont",
            signature: "scaledFont(for:)",
            isAsync: false,
        )
        // The signature path is what fans out into search-result
        // rendering; pin the format so a refactor doesn't drop the
        // kind prefix.
        #expect(symbol.displayString == "func scaledFont(for:)")
    }

    @Test("Search.MatchedSymbol displayString falls back to name when signature is nil or empty")
    func matchedSymbolDisplayWithoutSignature() {
        let typeSymbol = Search.MatchedSymbol(kind: "class", name: "UIFontMetrics")
        #expect(typeSymbol.displayString == "class UIFontMetrics")

        let emptySig = Search.MatchedSymbol(kind: "struct", name: "View", signature: "", isAsync: false)
        #expect(emptySig.displayString == "struct View")
    }

    // MARK: DocumentFormat

    @Test("Search.DocumentFormat cases are stable")
    func documentFormatCases() {
        // DocumentFormat backs the `format:` parameter in every
        // resource-render pathway (Services.ReadService, MCP
        // resources/read, CLI cupertino read). Renaming a case
        // would silently break those callers.
        let formats: [Search.DocumentFormat] = [.json, .markdown]
        #expect(formats.count == 2)
    }

    // MARK: Search.Result

    @Test("Search.Result init exposes every public field")
    func resultInit() {
        let availability = Search.PlatformAvailability(name: "iOS", introducedAt: "15.0")
        let symbol = Search.MatchedSymbol(kind: "struct", name: "Task")
        let result = Search.Result(
            uri: "apple-docs://swift/task",
            source: "apple-docs",
            framework: "Swift",
            title: "Task",
            summary: "A unit of asynchronous work.",
            filePath: "/tmp/task.json",
            wordCount: 100,
            rank: -1.5,
            availability: [availability],
            matchedSymbols: [symbol],
        )
        #expect(result.uri == "apple-docs://swift/task")
        #expect(result.source == "apple-docs")
        #expect(result.framework == "Swift")
        #expect(result.title == "Task")
        #expect(result.wordCount == 100)
        #expect(result.rank == -1.5)
        #expect(result.availability?.count == 1)
        #expect(result.matchedSymbols?.count == 1)
    }

    @Test("Search.Result.score inverts the BM25 rank")
    func resultScoreInvertsRank() {
        // The BM25 wire format uses negative scores (lower = better).
        // The public `score` flips the sign so consumers can sort
        // descending without thinking about the inversion. Pin that
        // contract.
        let r = Search.Result(
            uri: "x", source: "y", framework: "z",
            title: "t", summary: "s", filePath: "/", wordCount: 1, rank: -2.5,
        )
        #expect(r.score == 2.5)
    }

    @Test("Search.Result.availabilityString omits unavailable platforms")
    func resultAvailabilityStringFiltersUnavailable() {
        let platforms = [
            Search.PlatformAvailability(name: "iOS", introducedAt: "15.0"),
            Search.PlatformAvailability(name: "macOS", introducedAt: "12.0", deprecated: true),
            Search.PlatformAvailability(name: "tvOS", introducedAt: "15.0", unavailable: true),
        ]
        let r = Search.Result(
            uri: "x", source: "y", framework: "z",
            title: "t", summary: "s", filePath: "/", wordCount: 1, rank: 0,
            availability: platforms,
        )
        let str = r.availabilityString ?? ""
        #expect(str.contains("iOS 15.0+"))
        #expect(str.contains("macOS 12.0+ (deprecated)"))
        #expect(!str.contains("tvOS")) // unavailable filtered out
    }

    @Test("Search.Result encode/decode round-trips")
    func resultCodableRoundTrip() throws {
        let availability = Search.PlatformAvailability(name: "iOS", introducedAt: "15.0")
        let original = Search.Result(
            uri: "apple-docs://swift/task",
            source: "apple-docs",
            framework: "Swift",
            title: "Task",
            summary: "A unit of asynchronous work.",
            filePath: "/tmp/task.json",
            wordCount: 100,
            rank: -1.5,
            availability: [availability],
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Search.Result.self, from: data)
        #expect(decoded.uri == original.uri)
        #expect(decoded.title == original.title)
        #expect(decoded.rank == original.rank)
        #expect(decoded.availability?.first?.name == "iOS")
    }
}
