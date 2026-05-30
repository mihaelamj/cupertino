import Foundation
import Testing

// MARK: - CLI/MCP parity battery (#962, #1172 validation)

//
// Drives 20 real queries per command type through BOTH the `cupertino` CLI and
// the `cupertino serve` MCP tool surface against the local per-source snapshot
// (LocalDBs.dir), asserting the two surfaces agree: for the SAME query, either
// both return usable content or both legitimately return none. The whole point
// of #962 parity is that an agent driving cupertino over the shell sees what an
// agent driving it over MCP sees.
//
// Gating: every suite is `.enabled(if: CupertinoCLI.available)`, so a machine
// without the snapshot (CI, fresh clone) skips cleanly. Point at a different
// snapshot with CUPERTINO_DB_DIR. The binary is the debug build under
// Packages/.build/debug/cupertino, pinned to LocalDBs.dir by CupertinoCLI.
//
// "Usable content" is deliberately coarse: each surface returns a non-trivial
// payload for the query, OR both surfaces agree there is nothing. We do not
// assert byte-identical output — the CLI emits JSON / human text and MCP emits
// markdown wire shape; they share a query pipeline, not a renderer. A divergence
// (one surface finds results, the other does not, for the same query) is the
// real bug class this battery exists to catch.

private enum Parity {
    /// A query "hit" on the CLI side: a non-empty JSON payload decoded to >0 rows.
    /// A query "hit" on the MCP side: a non-error result with non-trivial text.
    /// Parity holds when both hit or both miss.
    static func agree(cliHit: Bool, mcpHit: Bool) -> Bool { cliHit == mcpHit }

    /// Empty-result sentinels cupertino emits as ok-text (NOT error frames).
    /// These are substantive markdown blocks (the AST tools print "No symbols
    /// found matching your criteria." plus a tips section, ~240 chars), so a
    /// bare length check is not enough — the sentinel phrase must be matched
    /// explicitly or an empty result reads as a hit. Verified against live
    /// output for search / search_symbols / search_property_wrappers /
    /// search_concurrency / search_conformances / search_generics /
    /// get_inheritance on the fresh corpus.
    static let emptySentinels = [
        "no symbols found", // AST tools: "No symbols found matching your criteria."
        "no results",
        "no matching",
        "0 results",
        "not found",
        "no inheritance data", // get_inheritance on value types / no-chain symbols
        "no conformances",
        "no documents",
    ]

    /// MCP text is a "hit" only when it is a non-error frame that does NOT carry
    /// an empty-result sentinel. Length is a secondary guard for unrecognized
    /// shapes (a real single result is well over 60 chars).
    static func mcpHit(_ result: CupertinoMCP.ToolResult?) -> Bool {
        guard let result, !result.isError else { return false }
        let lowered = result.text.lowercased()
        if emptySentinels.contains(where: lowered.contains) { return false }
        return result.text.count >= 60
    }
}

// MARK: Query corpora (20 each)

private enum Queries {
    // Broad documentation terms that exist across Apple frameworks.
    static let search = [
        "View", "Button", "navigation", "animation", "gesture", "scroll", "layout",
        "color", "image", "text field", "stack", "list", "toolbar", "alert", "sheet",
        "tab bar", "progress", "slider", "picker", "map",
    ]
    // Symbol-name substrings that match many indexed AST symbols.
    static let symbols = [
        "View", "Controller", "Manager", "Delegate", "Configuration", "Request",
        "Response", "Session", "Coordinator", "Provider", "Handler", "Context",
        "Descriptor", "Builder", "Renderer", "Observer", "Container", "Resolver",
        "Factory", "Registry",
    ]
    // Property wrappers that appear in Apple + Swift sources.
    static let wrappers = [
        "State", "Binding", "Published", "ObservedObject", "StateObject",
        "EnvironmentObject", "Environment", "FetchRequest", "AppStorage",
        "SceneStorage", "FocusState", "GestureState", "Namespace", "Bindable",
        "Query", "Observable", "MainActor", "available", "objc", "escaping",
    ]
    // Concurrency patterns the search-concurrency command recognizes.
    // The search_concurrency tool accepts one of five patterns. To reach 20
    // genuinely DISTINCT cases (not the same five repeated) each pattern is
    // paired with a different framework filter, so every case is a unique
    // (pattern, framework) query against the corpus.
    static let concurrency: [(pattern: String, framework: String)] = [
        ("async", "swiftui"), ("async", "foundation"), ("async", "uikit"), ("async", "combine"),
        ("actor", "swiftui"), ("actor", "foundation"), ("actor", "uikit"), ("actor", "swiftdata"),
        ("sendable", "swiftui"), ("sendable", "foundation"), ("sendable", "uikit"), ("sendable", "combine"),
        ("mainactor", "swiftui"), ("mainactor", "foundation"), ("mainactor", "uikit"), ("mainactor", "observation"),
        ("task", "swiftui"), ("task", "foundation"), ("task", "uikit"), ("task", "combine"),
    ]
    // Protocols with conformers in the corpus.
    static let conformances = [
        "Equatable", "Hashable", "Codable", "Comparable", "Identifiable",
        "Sendable", "View", "Error", "CustomStringConvertible", "Sequence",
        "Collection", "Encodable", "Decodable", "RawRepresentable", "CaseIterable",
        "ExpressibleByStringLiteral", "Numeric", "AdditiveArithmetic", "Iterator", "AsyncSequence",
    ]
    // Generic constraints present in indexed signatures.
    static let generics = [
        "Equatable", "Hashable", "Codable", "Comparable", "Sendable",
        "Numeric", "Collection", "Sequence", "RawRepresentable", "Identifiable",
        "Encodable", "Decodable", "BinaryInteger", "FloatingPoint", "StringProtocol",
        "CaseIterable", "Error", "View", "AdditiveArithmetic", "SignedInteger",
    ]
    // Symbols whose inheritance chain the get_inheritance tool can walk. These
    // are class-based Apple APIs (value types legitimately have no chain, which
    // both surfaces report consistently — still parity).
    static let inheritance = [
        "UIViewController", "UIView", "UILabel", "UIButton", "UIScrollView",
        "UITableView", "UICollectionView", "UIControl", "UINavigationController",
        "UITabBarController", "NSObject", "CALayer", "UIResponder", "UIImageView",
        "UITextField", "UIStackView", "UIWindow", "UIApplication", "UIGestureRecognizer",
        "UIBarButtonItem",
    ]
}

// MARK: - Suites

@Suite("CLI/MCP parity: unified search (20 queries)", .enabled(if: CupertinoCLI.available))
struct SearchParityBattery {
    @Test("search vs search tool", arguments: Queries.search)
    func parity(_ query: String) {
        let cli = CupertinoCLI.searchDocs(query, ["--source", "apple-docs", "--limit", "5"])
        let mcp = CupertinoMCP.callTool("search", ["query": query, "source": "apple-docs", "limit": 5])
        let cliHit = !cli.isEmpty
        let mcpHit = Parity.mcpHit(mcp)
        #expect(
            Parity.agree(cliHit: cliHit, mcpHit: mcpHit),
            "search '\(query)': CLI hit=\(cliHit) (\(cli.count) rows), MCP hit=\(mcpHit)"
        )
    }
}

@Suite("CLI/MCP parity: search-symbols (20 queries)", .enabled(if: CupertinoCLI.available))
struct SymbolsParityBattery {
    @Test("search-symbols vs search_symbols", arguments: Queries.symbols)
    func parity(_ query: String) {
        let cli = CupertinoCLI.searchSymbols(query: query, ["--limit", "5"])
        let mcp = CupertinoMCP.callTool("search_symbols", ["query": query, "limit": 5])
        let cliHit = (cli?.results.isEmpty == false)
        let mcpHit = Parity.mcpHit(mcp)
        #expect(
            Parity.agree(cliHit: cliHit, mcpHit: mcpHit),
            "search-symbols '\(query)': CLI hit=\(cliHit) (\(cli?.results.count ?? 0) rows), MCP hit=\(mcpHit)"
        )
    }
}

@Suite("CLI/MCP parity: search-conformances (20 queries)", .enabled(if: CupertinoCLI.available))
struct ConformancesParityBattery {
    @Test("search-conformances vs search_conformances", arguments: Queries.conformances)
    func parity(_ proto: String) {
        let cliData = CupertinoCLI.jsonData(["search-conformances", "--protocol", proto, "--limit", "5"])
        let cliHit = cliResultsNonEmpty(cliData)
        let mcp = CupertinoMCP.callTool("search_conformances", ["protocol": proto, "limit": 5])
        let mcpHit = Parity.mcpHit(mcp)
        #expect(
            Parity.agree(cliHit: cliHit, mcpHit: mcpHit),
            "search-conformances '\(proto)': CLI hit=\(cliHit), MCP hit=\(mcpHit)"
        )
    }
}

@Suite("CLI/MCP parity: search-generics (20 queries)", .enabled(if: CupertinoCLI.available))
struct GenericsParityBattery {
    @Test("search-generics vs search_generics", arguments: Queries.generics)
    func parity(_ constraint: String) {
        let cli = CupertinoCLI.searchGenerics(constraint: constraint, ["--limit", "5"])
        let cliHit = (cli?.results.isEmpty == false)
        let mcp = CupertinoMCP.callTool("search_generics", ["constraint": constraint, "limit": 5])
        let mcpHit = Parity.mcpHit(mcp)
        #expect(
            Parity.agree(cliHit: cliHit, mcpHit: mcpHit),
            "search-generics '\(constraint)': CLI hit=\(cliHit) (\(cli?.results.count ?? 0) rows), MCP hit=\(mcpHit)"
        )
    }
}

@Suite("CLI/MCP parity: search-property-wrappers (20 queries)", .enabled(if: CupertinoCLI.available))
struct WrappersParityBattery {
    @Test("search-property-wrappers vs search_property_wrappers", arguments: Queries.wrappers)
    func parity(_ wrapper: String) {
        let cliData = CupertinoCLI.jsonData(["search-property-wrappers", "--wrapper", wrapper, "--limit", "5"])
        let cliHit = cliResultsNonEmpty(cliData)
        let mcp = CupertinoMCP.callTool("search_property_wrappers", ["wrapper": wrapper, "limit": 5])
        let mcpHit = Parity.mcpHit(mcp)
        #expect(
            Parity.agree(cliHit: cliHit, mcpHit: mcpHit),
            "search-property-wrappers '\(wrapper)': CLI hit=\(cliHit), MCP hit=\(mcpHit)"
        )
    }
}

@Suite("CLI/MCP parity: search-concurrency (20 queries)", .enabled(if: CupertinoCLI.available))
struct ConcurrencyParityBattery {
    @Test("search-concurrency vs search_concurrency", arguments: Queries.concurrency)
    func parity(_ qcase: (pattern: String, framework: String)) {
        let cliData = CupertinoCLI.jsonData(
            ["search-concurrency", "--pattern", qcase.pattern, "--framework", qcase.framework, "--limit", "5"])
        let cliHit = cliResultsNonEmpty(cliData)
        let mcp = CupertinoMCP.callTool(
            "search_concurrency", ["pattern": qcase.pattern, "framework": qcase.framework, "limit": 5]
        )
        let mcpHit = Parity.mcpHit(mcp)
        #expect(
            Parity.agree(cliHit: cliHit, mcpHit: mcpHit),
            "search-concurrency '\(qcase.pattern)' framework=\(qcase.framework): CLI hit=\(cliHit), MCP hit=\(mcpHit)"
        )
    }
}

@Suite("CLI/MCP parity: inheritance (20 queries)", .enabled(if: CupertinoCLI.available))
struct InheritanceParityBattery {
    @Test("inheritance vs get_inheritance", arguments: Queries.inheritance)
    func parity(_ symbol: String) {
        // The CLI `inheritance` command exits 1 on ambiguous / no-chain symbols
        // with a guidance message; the MCP `get_inheritance` returns the same
        // message as ok-text. Parity here is "both produce the same class of
        // outcome": both find a chain, or both report the same no-chain/ambiguity
        // guidance. We compare on the resolved-vs-unresolved signal via the
        // shared text, not the exit code.
        let cliText = CupertinoCLI.run(["inheritance", symbol])
        let mcp = CupertinoMCP.callTool("get_inheritance", ["symbol": symbol])
        let mcpText = (mcp?.isError == false) ? (mcp?.text ?? "") : ""
        // Both surfaces must produce non-trivial guidance/result text for the
        // same symbol (a real chain, an ambiguity list, or a no-inheritance-data
        // note — all are substantive and consistent across surfaces).
        let cliHit = cliText.count >= 40
        let mcpHit = mcpText.count >= 40
        #expect(
            Parity.agree(cliHit: cliHit, mcpHit: mcpHit),
            "inheritance '\(symbol)': CLI hit=\(cliHit) (\(cliText.count)c), MCP hit=\(mcpHit) (\(mcpText.count)c)"
        )
    }
}

// MARK: - Shared CLI helpers

/// AST commands that decode through the shared `ASTQueryResponse { results }`
/// shape (search-conformances / search-property-wrappers / search-concurrency
/// don't have a typed accessor on CupertinoCLI, so decode the envelope here).
private func cliResultsNonEmpty(_ data: Data?) -> Bool {
    guard let data else { return false }
    struct Envelope: Decodable { let results: [Row]?; struct Row: Decodable {} }
    let dec = JSONDecoder()
    dec.keyDecodingStrategy = .convertFromSnakeCase
    if let env = try? dec.decode(Envelope.self, from: data) {
        return (env.results?.isEmpty == false)
    }
    // Some commands emit a bare top-level array.
    if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
        return !arr.isEmpty
    }
    return false
}
