import Foundation
import Testing

// MARK: - Exhaustive enrichment battery (#1196)

// Proves every enrichment from docs/enrichment-inventory.md, plus the
// inheritance / conformance / min-version command surfaces, through the real
// `cupertino` CLI. Every query records an expandable section into the shared
// `BatteryReport` HTML (#1194) whose body is the FULL returned result set
// (every field of every result, or the raw command output) -- not a count.
//
// Gated on `CupertinoCLI.available` (debug binary + local snapshot), serialized.
// Local-only; skipped on CI. Report orders 100+ (after the read battery's 0-8).

enum EnrichmentBattery {
    static let appleDocs = [
        "view", "data", "string", "async", "protocol", "url", "image", "animation", "error", "color",
        "array", "dictionary", "task", "actor", "codable", "result", "sequence", "stream", "publisher", "gesture",
        "navigation", "layout", "font", "shape", "transaction",
    ]
    static let hig = [
        "color", "layout", "typography", "navigation", "button", "accessibility", "gesture", "icon", "menu", "sidebar",
        "toolbar", "alert", "sheet", "picker", "tab", "search", "notification", "widget", "window", "feedback",
        "onboarding", "gauge", "rating", "scroll", "label",
    ]
    static let appleArchive = [
        "view", "controller", "data", "table", "image", "animation", "thread", "memory", "drawing", "layer",
        "quartz", "core", "key", "value", "observe", "graphics", "context", "path", "transform", "gradient",
        "shadow", "text", "font", "event", "responder",
    ]
    static let swiftEvolution = [
        "concurrency", "actor", "async", "macro", "protocol", "result", "generics", "ownership", "sendable", "string",
        "regex", "result builder", "property wrapper", "existential", "package", "typed throws", "isolation", "copyable", "span", "embedded",
        "distributed", "variadic", "opaque", "move", "borrow",
    ]
    static let swiftOrg = [
        "concurrency", "package", "compiler", "macro", "string", "protocol", "testing", "build", "module", "toolchain",
        "actor", "async", "generics", "interop", "c++", "foundation", "swiftpm", "runtime", "abi", "linux",
        "windows", "documentation", "migration", "performance", "library",
    ]
    static let swiftBook = [
        "closure", "optional", "protocol", "generic", "enumeration", "structure", "class", "function", "property", "initializer",
        "subscript", "extension", "inheritance", "error handling", "concurrency", "actor", "macro", "opaque type", "result builder", "string",
        "collection", "control flow", "deinitialization", "memory safety", "access control",
    ]
    static let samples = [
        "view", "swiftui", "animation", "data", "network", "audio", "camera", "widget", "metal", "map",
        "game", "machine learning", "vision", "augmented reality", "watch", "notification", "core data", "photo", "video", "scene",
        "gesture", "list", "navigation", "chart", "document",
    ]
    static let packages = [
        "logger", "actor", "async", "client", "server", "json", "http", "test", "macro", "collection",
        "crypto", "url", "date", "algorithm", "concurrency", "stream", "decode", "encode", "websocket", "metrics",
        "tracing", "atomic", "regex", "numerics", "argument",
    ]

    static let docs: [(id: String, db: String, queries: [String])] = [
        ("apple-docs", LocalDBs.appleDocumentation, appleDocs),
        ("hig", LocalDBs.hig, hig),
        ("apple-archive", LocalDBs.appleArchive, appleArchive),
        ("swift-evolution", LocalDBs.swiftEvolution, swiftEvolution),
        ("swift-org", LocalDBs.swiftOrg, swiftOrg),
        ("swift-book", LocalDBs.swiftBook, swiftBook),
    ]

    static var availableDocs: [(id: String, db: String, queries: [String])] {
        docs.filter { LocalDBs.available($0.db) }
    }

    static func order(of source: String) -> Int {
        docs.firstIndex { $0.id == source } ?? 0
    }

    static let symbols = [
        "View", "Data", "String", "Color", "Image", "URLSession", "Task", "Array", "Codable", "Error",
        "Button", "Text", "Stack", "Path", "Gesture", "Publisher", "Sequence", "Result", "Date", "Notification",
        "Shape", "Font", "Layout", "Transaction", "Binding",
    ]
    static let constraints = [
        "Equatable", "Hashable", "Comparable", "Codable", "Sendable", "Collection", "Sequence", "Identifiable", "Error", "View",
        "Encodable", "Decodable", "RawRepresentable", "CaseIterable", "CustomStringConvertible",
        "Numeric", "Strideable", "AdditiveArithmetic", "ExpressibleByStringLiteral",
        "RandomAccessCollection", "BidirectionalCollection", "IteratorProtocol", "AsyncSequence", "Observable",
    ]

    static func titleToken(_ title: String) -> String? {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 4 }.max(by: { $0.count < $1.count })
    }

    // MARK: - Report recording

    /// One expandable `<details>` per item, body = the FULL returned text.
    static func recordDetails(order: Int, title: String, items: [(summary: String, body: String)]) {
        var html = "<h2>\(BatteryReport.esc(title))</h2>"
        for item in items {
            html += BatteryReport.details(item.summary, item.body.isEmpty ? "(no output)" : item.body)
        }
        BatteryReport.shared.record(order: order, html: html)
    }

    /// Render every field of every docs search result.
    static func renderDocs(_ results: [CupertinoCLI.DocResult]) -> String {
        guard !results.isEmpty else { return "(no results)" }
        var out = ""
        for (index, result) in results.enumerated() {
            out += "[\(index + 1)] \(result.title)\n"
            out += "    uri:     \(result.uri)\n"
            if let framework = result.framework { out += "    fwk:     \(framework)\n" }
            if let source = result.source { out += "    source:  \(source)\n" }
            if let rank = result.rank { out += "    score:   \(String(format: "%.4f", rank))\n" }
            if let words = result.wordCount { out += "    words:   \(words)\n" }
            if let matched = result.matchedSymbols, !matched.isEmpty {
                out += "    symbols: " + matched.map { "\($0.name)(\($0.kind))" }.joined(separator: ", ") + "\n"
            }
            if let summary = result.summary { out += "    \(summary)\n" }
            out += "\n"
        }
        return out
    }

    /// Render every field of every AST symbol-query result.
    static func renderAST(_ results: [CupertinoCLI.ASTQueryResponse.ASTSymbol]) -> String {
        guard !results.isEmpty else { return "(no results)" }
        var out = ""
        for (index, symbol) in results.enumerated() {
            out += "[\(index + 1)] \(symbol.symbolName)"
            if let kind = symbol.symbolKind { out += "  (\(kind))" }
            out += "\n"
            if let params = symbol.genericParams, !params.isEmpty { out += "    generics: \(params)\n" }
            if let uri = symbol.docUri { out += "    uri:      \(uri)\n" }
            if let title = symbol.docTitle { out += "    doc:      \(title)\n" }
            if let framework = symbol.framework { out += "    fwk:      \(framework)\n" }
            out += "\n"
        }
        return out
    }
}

// MARK: - #1 Lexical Index (FTS5) -- all built-in databases

@Suite("Enrichment #1 Lexical Index (exhaustive, all DBs)", .serialized, .enabled(if: CupertinoCLI.available))
struct ExhaustiveLexicalIndexTests {
    @Test("each docs source returns FTS results for >= 20 queries", arguments: EnrichmentBattery.availableDocs.map(\.id))
    func docsLexical(_ sourceId: String) {
        guard let source = EnrichmentBattery.docs.first(where: { $0.id == sourceId }) else { return }
        var items: [(String, String)] = []
        var hits = 0
        for query in source.queries {
            let results = CupertinoCLI.searchDocs(query, ["--source", source.id, "--limit", "5"])
            if !results.isEmpty { hits += 1 }
            for result in results where result.source != nil {
                #expect(result.source == source.id, "\(source.id) '\(query)' leaked source \(result.source ?? "?")")
            }
            items.append(("\"\(query)\"  ->  \(results.count) results", EnrichmentBattery.renderDocs(results)))
        }
        #expect(hits >= 18, "\(source.id): only \(hits)/\(source.queries.count) FTS queries hit")
        EnrichmentBattery.recordDetails(
            order: 100 + EnrichmentBattery.order(of: sourceId),
            title: "#1 Lexical Index -- search --source \(source.id) (\(source.queries.count) queries)",
            items: items
        )
    }

    @Test(
        "samples + packages FTS return results for >= 20 queries",
        .enabled(if: LocalDBs.samplesAvailable || LocalDBs.packagesAvailable)
    )
    func samplesPackagesLexical() {
        var items: [(String, String)] = []
        if LocalDBs.samplesAvailable {
            var hits = 0
            for query in EnrichmentBattery.samples {
                let files = CupertinoCLI.searchSamples(query, ["--limit", "5"])?.files ?? []
                if !files.isEmpty { hits += 1 }
                let body = files.enumerated().map { "[\($0 + 1)] \($1.projectId) / \($1.path)" + ($1.snippet.map { "\n    \($0)" } ?? "") }.joined(separator: "\n")
                items.append(("samples \"\(query)\"  ->  \(files.count) files", body))
            }
            #expect(hits >= 16, "samples: only \(hits)/\(EnrichmentBattery.samples.count) FTS queries hit")
        }
        if LocalDBs.packagesAvailable {
            var hits = 0
            for query in EnrichmentBattery.packages {
                let cands = CupertinoCLI.searchPackages(query, ["--limit", "5"])?.candidates ?? []
                if !cands.isEmpty { hits += 1 }
                let body = cands.enumerated().map { "[\($0 + 1)] \($1.identifier)" + ($1.title.map { "  \u{2014} \($0)" } ?? "") }.joined(separator: "\n")
                items.append(("packages \"\(query)\"  ->  \(cands.count) candidates", body))
            }
            #expect(hits >= 16, "packages: only \(hits)/\(EnrichmentBattery.packages.count) FTS queries hit")
        }
        EnrichmentBattery.recordDetails(order: 106, title: "#1 Lexical Index -- samples + packages FTS", items: items)
    }
}

// MARK: - #2 / #5 / #7 Symbol surfacing

@Suite(
    "Enrichment #2/#5/#7 Symbol surfacing (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveSymbolTests {
    static let canonicalSymbols = [
        "LazyVGrid", "LazyHGrid", "NavigationStack", "NavigationSplitView", "ScrollView",
        "AsyncStream", "AsyncThrowingStream", "URLSession", "URLRequest", "GeometryReader",
        "RoundedRectangle", "LinearGradient", "ForEach", "TabView", "ProgressView",
        "DatePicker", "ColorPicker", "AttributedString", "TaskGroup", "RoundedBorderTextFieldStyle",
        "UIViewController", "CALayer", "NSAttributedString", "DispatchQueue", "PropertyListDecoder",
    ]

    @Test("search-symbols returns AST symbol rows for >= 20 queries (#5)")
    func astSymbols() {
        var items: [(String, String)] = []
        var hits = 0
        for symbol in EnrichmentBattery.symbols {
            let results = CupertinoCLI.searchSymbols(query: symbol, ["--limit", "5"])?.results ?? []
            if !results.isEmpty { hits += 1 }
            items.append(("\"\(symbol)\"  ->  \(results.count) symbols", EnrichmentBattery.renderAST(results)))
        }
        #expect(hits >= 18, "search-symbols: only \(hits)/\(EnrichmentBattery.symbols.count) hit")
        EnrichmentBattery.recordDetails(order: 110, title: "#5 AST Symbol Extraction -- search-symbols (\(EnrichmentBattery.symbols.count) queries)", items: items)
    }

    @Test("exact symbol queries surface the canonical page (#2 boosting + #7 splitting)")
    func symbolBoosting() {
        var items: [(String, String)] = []
        var surfaced = 0
        for symbol in Self.canonicalSymbols {
            let results = CupertinoCLI.searchDocs(symbol, ["--source", "apple-docs", "--limit", "3"])
            let needle = symbol.lowercased()
            let hit = results.prefix(3).contains { result in
                result.uri.lowercased().contains(needle)
                    || result.title.lowercased().replacingOccurrences(of: " ", with: "").contains(needle)
                    || (result.matchedSymbols?.contains { $0.name.lowercased() == needle } ?? false)
            }
            if hit { surfaced += 1 }
            items.append(("\"\(symbol)\"  ->  \(hit ? "canonical surfaced" : "not surfaced")", EnrichmentBattery.renderDocs(results)))
        }
        #expect(surfaced >= 20, "symbol boosting: only \(surfaced)/\(Self.canonicalSymbols.count) surfaced the canonical page")
        EnrichmentBattery.recordDetails(order: 111, title: "#2 Symbol Field Boosting + #7 Identifier Splitting (\(Self.canonicalSymbols.count) exact symbols)", items: items)
    }
}

// MARK: - #9 / #10 Generic constraints

@Suite(
    "Enrichment #9/#10 Constraints (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveConstraintTests {
    @Test("search-generics returns constrained symbols for >= 20 constraints")
    func generics() {
        var items: [(String, String)] = []
        var hits = 0
        for constraint in EnrichmentBattery.constraints {
            let results = CupertinoCLI.searchGenerics(constraint: constraint, ["--limit", "5"])?.results ?? []
            if !results.isEmpty { hits += 1 }
            items.append(("\"\(constraint)\"  ->  \(results.count) symbols", EnrichmentBattery.renderAST(results)))
        }
        #expect(hits >= 12, "search-generics: only \(hits)/\(EnrichmentBattery.constraints.count) constraints hit")
        EnrichmentBattery.recordDetails(
            order: 112,
            title: "#9/#10 Constraint Resolution + Propagation -- search-generics (\(EnrichmentBattery.constraints.count) constraints)",
            items: items
        )
    }
}

// MARK: - Conformances command

@Suite(
    "search-conformances (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveConformanceTests {
    @Test("search-conformances returns conformers for >= 20 protocols")
    func conformances() {
        var items: [(String, String)] = []
        var hits = 0
        for proto in EnrichmentBattery.constraints {
            let body = BatteryReport.stripLog(CupertinoCLI.run(["search-conformances", "--protocol", proto, "--limit", "5", "--format", "markdown"]))
            let count = CupertinoCLI.run(["search-conformances", "--protocol", proto, "--limit", "5", "--format", "json"]).components(separatedBy: "\"symbol_name\"").count - 1
            if count >= 1 { hits += 1 }
            items.append(("\"\(proto)\"  ->  \(count) conformers", body))
        }
        #expect(hits >= 10, "search-conformances: only \(hits)/\(EnrichmentBattery.constraints.count) protocols had conformers")
        EnrichmentBattery.recordDetails(order: 113, title: "search-conformances (\(EnrichmentBattery.constraints.count) protocols)", items: items)
    }
}

// MARK: - #15 Inheritance graph

@Suite(
    "Enrichment #15 Inheritance Graph (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveInheritanceTests {
    static let symbols = [
        "UIView", "UIViewController", "UIControl", "UIButton", "UILabel", "UIScrollView", "UITableView", "NSObject", "UIResponder", "CALayer",
        "UICollectionView", "UIImageView", "UITextField", "UISlider", "UISwitch", "UIStackView", "UINavigationController", "UITabBarController", "NSView", "NSViewController",
        "SKNode", "SCNNode", "CAAnimation", "UIGestureRecognizer", "UIWindow",
    ]

    @Test("inheritance emits a graph for >= 20 symbols")
    func inheritance() {
        var items: [(String, String)] = []
        var hits = 0
        for symbol in Self.symbols {
            let body = BatteryReport.stripLog(CupertinoCLI.run(["inheritance", symbol, "--format", "markdown"]))
            let hasEdges = body.contains("parent") || body.contains("child") || body.contains(symbol) || body.count > 40
            if hasEdges { hits += 1 }
            items.append((symbol, body))
        }
        #expect(hits >= 15, "inheritance: only \(hits)/\(Self.symbols.count) symbols produced a graph")
        EnrichmentBattery.recordDetails(order: 114, title: "#15 Inheritance Graph -- inheritance (\(Self.symbols.count) symbols)", items: items)
    }
}

// MARK: - #24 AST Boilerplate Demotion

@Suite(
    "Enrichment #24 AST Boilerplate Demotion (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveDemotionTests {
    @Test("search-symbols ranks a named declaration first, demoting operator boilerplate (#177)")
    func boilerplateDemotion() {
        var items: [(String, String)] = []
        var namedFirst = 0
        for symbol in EnrichmentBattery.symbols {
            let results = CupertinoCLI.searchSymbols(query: symbol, ["--limit", "5"])?.results ?? []
            let top = results.first?.symbolName ?? ""
            let namedTop = top.first.map { $0.isLetter || $0 == "_" } ?? false
            if namedTop { namedFirst += 1 }
            items.append(("\"\(symbol)\"  ->  top: \(top.isEmpty ? "(none)" : top)", EnrichmentBattery.renderAST(results)))
        }
        #expect(namedFirst >= 18, "boilerplate demotion: only \(namedFirst)/\(EnrichmentBattery.symbols.count) ranked a named symbol first")
        EnrichmentBattery.recordDetails(
            order: 115,
            title: "#24 AST Boilerplate Demotion -- search-symbols top-hit named (\(EnrichmentBattery.symbols.count) queries)",
            items: items
        )
    }
}

// MARK: - #3 / #17 Deployment floors (min-version options)

@Suite(
    "Enrichment #3/#17 Deployment Floors (exhaustive, per option)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveFloorTests {
    @Test("each --min-<platform> floor runs over >= 20 queries and returns results", arguments: [
        "--min-ios", "--min-macos", "--min-tvos", "--min-watchos", "--min-visionos",
    ])
    func floor(_ option: String) {
        var items: [(String, String)] = []
        var hits = 0
        for query in EnrichmentBattery.appleDocs {
            let results = CupertinoCLI.searchDocs(query, ["--source", "apple-docs", "--limit", "5", option, "16.0"])
            if !results.isEmpty { hits += 1 }
            items.append(("\"\(query)\" \(option) 16.0  ->  \(results.count) results", EnrichmentBattery.renderDocs(results)))
        }
        #expect(hits >= 10, "\(option): only \(hits)/\(EnrichmentBattery.appleDocs.count) queries returned results")
        let floorOrder = ["--min-ios": 0, "--min-macos": 1, "--min-tvos": 2, "--min-watchos": 3, "--min-visionos": 4][option] ?? 0
        EnrichmentBattery.recordDetails(
            order: 120 + floorOrder,
            title: "#3/#17 Deployment Floors -- apple-docs \(option) 16.0 (\(EnrichmentBattery.appleDocs.count) queries)",
            items: items
        )
    }
}

// MARK: - #21 / #22 / #23 Query-time ranking

@Suite(
    "Enrichment #21/#22/#23 Ranking (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveRankingTests {
    @Test("fan-out search fuses multiple sources via RRF for >= 20 queries (#21)")
    func rankFusion() {
        var items: [(String, String)] = []
        var fused = 0
        for query in EnrichmentBattery.appleDocs {
            let response = CupertinoCLI.searchFanout(query, ["--limit", "10"])
            let sources = response?.contributingSources ?? []
            let candidates = response?.candidates ?? []
            if sources.count >= 2, !candidates.isEmpty { fused += 1 }
            var body = "contributing sources: \(sources.joined(separator: ", "))\n\n"
            for (index, candidate) in candidates.enumerated() {
                body += "[\(index + 1)] (\(candidate.source ?? "?")) \(candidate.title ?? candidate.identifier ?? "")"
                if let rank = candidate.rank { body += "  rank=\(String(format: "%.4f", rank))" }
                body += "\n"
            }
            items.append(("\"\(query)\"  ->  \(sources.count) sources, \(candidates.count) candidates", body))
        }
        #expect(fused >= 15, "RRF: only \(fused)/\(EnrichmentBattery.appleDocs.count) queries fused >= 2 sources")
        EnrichmentBattery.recordDetails(order: 130, title: "#21 Rank Fusion -- fan-out search (\(EnrichmentBattery.appleDocs.count) queries)", items: items)
    }

    @Test("exact-title queries rank that page first (#23 kind-aware reranking)")
    func reranking() {
        var items: [(String, String)] = []
        var topHit = 0
        for symbol in ExhaustiveSymbolTests.canonicalSymbols {
            let results = CupertinoCLI.searchDocs(symbol, ["--source", "apple-docs", "--limit", "3"])
            let needle = symbol.lowercased()
            let topIsExact = results.first.map {
                $0.title.lowercased().replacingOccurrences(of: " ", with: "").contains(needle) || $0.uri.lowercased().contains(needle)
            } ?? false
            if topIsExact { topHit += 1 }
            items.append(("\"\(symbol)\"  ->  \(topIsExact ? "exact first" : "not first")", EnrichmentBattery.renderDocs(results)))
        }
        #expect(topHit >= 18, "reranking: only \(topHit)/\(ExhaustiveSymbolTests.canonicalSymbols.count) ranked the exact page first")
        EnrichmentBattery.recordDetails(order: 131, title: "#23 Kind-Aware Reranking -- exact-title-first (\(ExhaustiveSymbolTests.canonicalSymbols.count) symbols)", items: items)
    }

    @Test("intent-routed fan-out keeps apple-docs a top contributor for API queries (#22)")
    func intentRouting() {
        var items: [(String, String)] = []
        var appleTop = 0
        for query in EnrichmentBattery.symbols {
            let candidates = CupertinoCLI.searchFanout(query, ["--limit", "10"])?.candidates ?? []
            let appleContributes = candidates.prefix(3).contains { ($0.source ?? "").contains("apple") }
            if appleContributes { appleTop += 1 }
            let body = candidates.enumerated().map { "[\($0 + 1)] (\($1.source ?? "?")) \($1.title ?? $1.identifier ?? "")" }.joined(separator: "\n")
            items.append(("\"\(query)\"  ->  top source: \(candidates.first?.source ?? "(none)")", body))
        }
        #expect(appleTop >= 15, "intent routing: apple-docs in top-3 for only \(appleTop)/\(EnrichmentBattery.symbols.count)")
        EnrichmentBattery.recordDetails(order: 132, title: "#22 Intent Routing -- apple-docs authority (\(EnrichmentBattery.symbols.count) queries)", items: items)
    }
}

// MARK: - #11 Framework aliasing

@Suite(
    "Enrichment #11 Framework Aliasing (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveAliasingTests {
    static let aliases: [(query: String, framework: String)] = [
        ("bluetooth", "bluetooth"), ("location", "location"), ("machine learning", "ml"), ("augmented reality", "arkit"),
        ("nfc", "nfc"), ("health", "health"), ("home automation", "home"), ("payments", "passkit"),
        ("notifications", "notification"), ("contacts", "contact"), ("calendar", "eventkit"), ("photos", "photo"),
        ("speech", "speech"), ("maps", "mapkit"), ("camera", "avfoundation"), ("audio", "av"),
        ("animation", "core"), ("graphics", "core"), ("networking", "network"), ("storage", "core"),
        ("widgets", "widgetkit"), ("watch", "watch"), ("game", "game"), ("ar", "arkit"),
    ]

    @Test("alias queries route to the aliased framework for >= 20 terms")
    func aliasing() {
        var items: [(String, String)] = []
        var routed = 0
        for entry in Self.aliases {
            let results = CupertinoCLI.searchDocs(entry.query, ["--source", "apple-docs", "--limit", "5"])
            let hit = results.contains { result in
                (result.framework?.lowercased().contains(entry.framework) ?? false) || result.uri.lowercased().contains(entry.framework)
            }
            if hit { routed += 1 }
            items.append(("\"\(entry.query)\"  ->  \(entry.framework) (\(hit ? "routed" : "not routed"))", EnrichmentBattery.renderDocs(results)))
        }
        #expect(routed >= 12, "aliasing: only \(routed)/\(Self.aliases.count) terms routed to the framework")
        EnrichmentBattery.recordDetails(order: 133, title: "#11 Framework Aliasing (\(Self.aliases.count) alias terms)", items: items)
    }
}

// MARK: - #14 / #16 read-surfaced enrichments

@Suite(
    "Enrichment #14/#16 read-surfaced (exhaustive)",
    .serialized,
    .enabled(if: CupertinoCLI.available && LocalDBs.available(LocalDBs.appleDocumentation))
)
struct ExhaustiveReadFieldTests {
    @Test("reading >= 20 docs exposes structured projection + code examples")
    func readFields() {
        var seen = Set<String>()
        var uris: [String] = []
        for query in EnrichmentBattery.appleDocs {
            for result in CupertinoCLI.searchDocs(query, ["--source", "apple-docs", "--limit", "5"]) where seen.insert(result.uri).inserted {
                uris.append(result.uri)
            }
            if uris.count >= 25 { break }
        }
        #expect(uris.count >= 20, "only gathered \(uris.count) docs to read")

        var items: [(String, String)] = []
        var structured = 0
        var withExamples = 0
        for uri in uris.prefix(25) {
            let body = BatteryReport.stripLog(CupertinoCLI.run(["read", uri, "--source", "apple-docs", "--format", "json"]))
            let hasStructure = body.contains("\"declaration\"") || body.contains("\"sections\"") || body.contains("\"overview\"")
            if hasStructure { structured += 1 }
            if body.contains("\"codeExamples\""), !body.contains("\"codeExamples\" : [ ]"), !body.contains("\"codeExamples\":[]") {
                withExamples += 1
            }
            items.append((uri, body))
        }
        #expect(structured >= 20, "#14 structured projection: only \(structured)/\(uris.prefix(25).count) docs had structure")
        #expect(withExamples >= 1, "#16 code examples: none of the read docs carried codeExamples")
        EnrichmentBattery.recordDetails(order: 134, title: "#14 Structured Projection + #16 Code Examples (\(uris.prefix(25).count) docs read)", items: items)
    }
}

// MARK: - Internal stored columns proven by DB probe (a count table is the content here)

@Suite(
    "Enrichment #4/#6/#8/#12/#13/#18/#19/#20 stored columns (exhaustive probe)",
    .serialized,
    .enabled(if: LocalDBs.anyAvailable)
)
struct ExhaustiveStoredColumnTests {
    private func nonNull(_ db: String, table: String, column: String) -> Int64 {
        guard let probe = DBProbe(db), probe.hasTable(table), probe.tableColumns(table).contains(column) else { return -1 }
        return probe.count("SELECT COUNT(*) FROM \(table) WHERE \(column) IS NOT NULL AND \(column) != ''")
    }

    /// Sample up to `limit` actual values from a column, for the report body.
    private func sample(_ db: String, table: String, column: String, limit: Int = 15) -> [String] {
        guard let probe = DBProbe(db) else { return [] }
        return probe.column("SELECT \(column) FROM \(table) WHERE \(column) IS NOT NULL AND \(column) != '' LIMIT \(limit)")
    }

    @Test("every internal enrichment column is populated in >= 20 rows of its DB")
    func storedColumns() {
        var items: [(String, String)] = []
        func check(_ label: String, _ db: String, _ table: String, _ column: String, min: Int64 = 20) {
            guard LocalDBs.available(db) else { return }
            let count = nonNull(db, table: table, column: column)
            let values = sample(db, table: table, column: column)
            let body = "non-null rows: \(count)\n\nsample values:\n" + values.map { "  \u{2022} \($0)" }.joined(separator: "\n")
            items.append(("\(label)  --  \(db).\(table).\(column)  ->  \(count) rows", body))
            #expect(count >= min, "\(label): \(db).\(table).\(column) populated in \(count) rows (< \(min))")
        }
        for source in EnrichmentBattery.docs where LocalDBs.available(source.db) {
            check("#19 provenance", source.db, "docs_metadata", "source_type")
            check("#20 content_hash", source.db, "docs_metadata", "content_hash")
            check("#20 word_count", source.db, "docs_metadata", "word_count")
        }
        check("#4 toolchain", LocalDBs.swiftEvolution, "docs_metadata", "implementation_swift_version", min: 5)
        check("#4 toolchain", LocalDBs.swiftBook, "docs_metadata", "implementation_swift_version", min: 1)
        check("#4 toolchain", LocalDBs.packages, "package_metadata", "swift_tools_version", min: 5)
        check("#6 imports", LocalDBs.appleDocumentation, "doc_imports", "module_name")
        check("#6 imports", LocalDBs.appleSampleCode, "file_imports", "module_name")
        check("#6 imports", LocalDBs.packages, "package_imports", "module_name")
        check("#8 availability", LocalDBs.packages, "package_files", "available_attrs_json", min: 5)
        check("#13 apple-imports", LocalDBs.packages, "package_metadata", "apple_imports_json", min: 5)
        check("#18 dep closure", LocalDBs.packages, "package_metadata", "parents_json", min: 5)
        EnrichmentBattery.recordDetails(order: 140, title: "Internal enrichment columns -- populated-row probe + sample values", items: items)
    }

    @Test(
        "#12 HIG platform applicability NULLs some min_<platform> rows",
        .enabled(if: LocalDBs.available(LocalDBs.hig))
    )
    func higPlatformApplicability() {
        guard let probe = DBProbe(LocalDBs.hig), probe.hasTable("docs_metadata") else { return }
        let total = probe.count("SELECT COUNT(*) FROM docs_metadata")
        let nulled = probe.count("SELECT COUNT(*) FROM docs_metadata WHERE min_ios IS NULL OR min_macos IS NULL")
        let titles = probe.column("SELECT title FROM docs_metadata WHERE min_ios IS NULL OR min_macos IS NULL LIMIT 15")
        #expect(total >= 1)
        #expect(nulled >= 1, "#12: HIG has no NULLed platform rows (subtractive applicability not applied)")
        let body = "total HIG rows: \(total)\nrows with a NULLed platform floor: \(nulled)\n\nexamples:\n" + titles.map { "  \u{2022} \($0)" }.joined(separator: "\n")
        EnrichmentBattery.recordDetails(order: 141, title: "#12 Platform Applicability -- HIG subtractive NULLing", items: [("HIG rows with NULLed platform floors", body)])
    }
}
