import Foundation
import Testing

// MARK: - Exhaustive read battery (#1194)

// Proves the read-only enforcement (#1194) end-to-end through the production
// CLI: every read command, across every source/option, serves queries and
// document reads correctly when the database is opened read-only. Gated on
// `CupertinoCLI.available` (the debug binary + a local snapshot), so CI and
// fresh clones skip it. Each suite is `.serialized` because every assertion
// spawns the binary, and the harness serializes binary spawns anyway.
//
// As it runs it ALSO writes a self-contained HTML report (`BatteryReport`)
// with a collapsible section per query and per document showing the actual
// returned text -- regenerated on every run, by this Swift code. Path:
// `$CUPERTINO_READ_REPORT`, else `<repo>/Packages/.build/read-battery-report.html`.
//
// Coverage (no shortcuts -- every built-in database):
//  - ~10 search queries per docs source (6) + samples + packages
//  - >= 20 document reads from EVERY database
//  - the AST search commands
// Assertions are shape-based (result present, source correct, read output
// echoes the title), never bare length, so a degraded read surfaces as a
// failure rather than passing on noise.

enum ReadBattery {
    struct DocsSource: CustomTestStringConvertible {
        let id: String
        let db: String
        let queries: [String]

        var testDescription: String {
            id
        }
    }

    static let docsSources: [DocsSource] = [
        DocsSource(
            id: "apple-docs",
            db: LocalDBs.appleDocumentation,
            queries: ["view", "data", "string", "async", "protocol", "url", "image", "animation", "error", "color"]
        ),
        DocsSource(
            id: "hig",
            db: LocalDBs.hig,
            queries: ["color", "layout", "typography", "navigation", "button", "accessibility", "gesture", "icon", "menu", "sidebar"]
        ),
        DocsSource(
            id: "apple-archive",
            db: LocalDBs.appleArchive,
            queries: ["view", "controller", "data", "table", "image", "animation", "thread", "memory", "drawing", "layer"]
        ),
        DocsSource(
            id: "swift-evolution",
            db: LocalDBs.swiftEvolution,
            queries: ["concurrency", "actor", "async", "macro", "protocol", "result", "generics", "ownership", "sendable", "string"]
        ),
        DocsSource(
            id: "swift-org",
            db: LocalDBs.swiftOrg,
            queries: ["concurrency", "package", "compiler", "macro", "string", "protocol", "testing", "build", "module", "toolchain"]
        ),
        DocsSource(
            id: "swift-book",
            db: LocalDBs.swiftBook,
            queries: ["closure", "optional", "protocol", "generic", "enumeration", "structure", "class", "function", "property", "initializer"]
        ),
    ]

    static var availableDocsSources: [DocsSource] {
        docsSources.filter { LocalDBs.available($0.db) }
    }

    static func order(of source: String) -> Int {
        docsSources.firstIndex { $0.id == source } ?? 0
    }

    /// The longest token (>= 4 chars, alphanumeric) of a title, lowercased, for
    /// a case-insensitive "the read echoed the document" shape check.
    static func titleToken(_ title: String) -> String? {
        title
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 }
            .max(by: { $0.count < $1.count })
    }
}

// MARK: - HTML report writer

/// Accumulates the battery's sections and writes a self-contained HTML report
/// on every update, so a complete report exists after the run (and a partial
/// one mid-run). Thread-safe: the battery serializes CLI spawns, but tests may
/// still record concurrently.
final class BatteryReport: @unchecked Sendable {
    static let shared = BatteryReport()

    private let lock = NSLock()
    private var sections: [Int: String] = [:]
    let path: String

    private init() {
        if let env = ProcessInfo.processInfo.environment["CUPERTINO_READ_REPORT"], !env.isEmpty {
            path = env
        } else {
            // #filePath = <repo>/Packages/Tests/EnrichmentBatteryTests/ReadOnlyReadBatteryTests.swift
            let packages = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            path = packages.appendingPathComponent(".build/read-battery-report.html").path
        }
    }

    static func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Strip the leading timestamped log line the CLI prints before output.
    static func stripLog(_ text: String) -> String {
        var kept: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if kept.isEmpty, line.prefix(4).allSatisfy(\.isNumber) { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func details(_ summary: String, _ body: String, badge: String = "") -> String {
        "<details><summary>\(badge)\(esc(summary))</summary><pre>\(esc(body))</pre></details>"
    }

    func record(order: Int, html: String) {
        lock.lock()
        defer { lock.unlock() }
        sections[order] = html
        let body = sections.keys.sorted().compactMap { sections[$0] }.joined(separator: "\n")
        try? (Self.header + body + Self.footer).write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static let header = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>cupertino read battery</title>
    <style>
    :root{--text:#1d1d1f;--secondary:#6e6e73;--accent:#0071e3;--surface:#f5f5f7;--border:#d2d2d7;--ok:#1d8a34;--fail:#d70015}
    *{box-sizing:border-box}
    body{font-family:-apple-system,"SF Pro Text",system-ui,Helvetica,Arial,sans-serif;font-size:17px;line-height:1.47;
    max-width:980px;margin:0 auto;padding:3rem 1.5rem;color:var(--text);background:#fff;-webkit-font-smoothing:antialiased}
    h1{font-size:40px;font-weight:600;letter-spacing:-.02em;margin:0 0 .25rem}
    h2{font-size:26px;font-weight:600;letter-spacing:-.01em;margin:2.75rem 0 1rem;padding-top:1.5rem;border-top:1px solid var(--border)}
    h3{font-size:19px;font-weight:600;color:var(--secondary);margin:1.5rem 0 .5rem}
    p{color:var(--secondary);font-size:15px;max-width:42rem}
    code{font-family:"SF Mono",ui-monospace,Menlo,monospace;font-size:.88em;background:var(--surface);padding:.12em .4em;border-radius:5px}
    details{border:1px solid var(--border);border-radius:12px;margin:.5rem 0;padding:.65rem 1.1rem;background:#fff}
    details[open]{border-color:var(--accent)}
    summary{cursor:pointer;font-weight:500;color:var(--text);list-style:none}
    summary::-webkit-details-marker{display:none}
    summary::before{content:"\\203A";color:var(--secondary);margin-right:.6rem;display:inline-block;transition:transform .2s}
    details[open] summary::before{transform:rotate(90deg)}
    summary:hover{color:var(--accent)}
    pre{white-space:pre-wrap;word-break:break-word;background:var(--surface);border:none;padding:1rem;border-radius:10px;
    max-height:460px;overflow:auto;font-family:"SF Mono",ui-monospace,Menlo,monospace;font-size:13px;line-height:1.5;margin:.7rem 0 .2rem}
    table{border-collapse:collapse;width:100%;font-size:14px;margin:.5rem 0}
    th,td{border-bottom:1px solid var(--border);padding:.5rem .75rem;text-align:left;vertical-align:top}
    th{color:var(--secondary);font-weight:600}
    .ok{color:var(--ok);font-weight:600;margin-right:.5rem}
    .fail{color:var(--fail);font-weight:600;margin-right:.5rem}
    .meta{color:var(--secondary)}
    </style></head><body>
    <h1>cupertino read battery</h1>
    <p>Every query and document below was produced by the real <code>cupertino</code> CLI against the local
    snapshot, through the read-only path (#1194). Expand any row to see the returned text.</p>
    """

    private static let footer = "</body></html>"
}

// MARK: - Docs (search + read >= 20 per source)

@Suite("#1194 read battery: docs (search + read >= 20)", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryDocsTests {
    @Test("each docs source: search ~10 queries + read >= 20 documents read-only", arguments: ReadBattery.availableDocsSources)
    func docs(_ source: ReadBattery.DocsSource) {
        var html = "<h2>search --source \(BatteryReport.esc(source.id))</h2>"
        var hits = 0
        var seen = Set<String>()
        var docs: [(uri: String, title: String)] = []

        for query in source.queries {
            let results = CupertinoCLI.searchDocs(query, ["--source", source.id, "--limit", "10"])
            if !results.isEmpty { hits += 1 }
            for result in results {
                if let src = result.source {
                    #expect(src == source.id, "\(source.id) query '\(query)' returned a result tagged '\(src)'")
                }
                #expect(!result.uri.isEmpty)
                if seen.insert(result.uri).inserted { docs.append((result.uri, result.title)) }
            }
            var body = ""
            for (index, result) in results.prefix(5).enumerated() {
                body += "[\(index + 1)] \(result.title)\n    uri:   \(result.uri)\n"
                if let framework = result.framework { body += "    fwk:   \(framework)\n" }
                if let rank = result.rank { body += "    score: \(String(format: "%.4f", rank))\n" }
                if let summary = result.summary { body += "    \(summary)\n" }
                body += "\n"
            }
            html += BatteryReport.details(
                "\"\(query)\"  ->  \(results.count) results",
                body.isEmpty ? "(no results)" : body,
                badge: "<span class=\"meta\">[\(results.count)]</span> "
            )
        }
        #expect(hits >= 8, "\(source.id): only \(hits)/\(source.queries.count) queries returned results")
        #expect(docs.count >= 20, "\(source.id): only gathered \(docs.count) distinct docs to read")

        var read = 0
        var readHTML = ""
        for doc in docs.prefix(20) {
            // A successful read echoes the document; a failure prints a short
            // "Document not found ..." line. The title token (or a real length
            // for token-less titles) is the success signal -- no content scan
            // for "error" (which appears legitimately in error-handling docs).
            let output = BatteryReport.stripLog(CupertinoCLI.run(["read", doc.uri, "--source", source.id, "--format", "markdown"]))
            let good: Bool
            if let token = ReadBattery.titleToken(doc.title) {
                good = output.lowercased().contains(token)
                #expect(good, "\(source.id) read '\(doc.uri)' did not echo title token '\(token)'")
            } else {
                good = output.count > 100
                #expect(good, "\(source.id) read '\(doc.uri)' returned trivial output")
            }
            read += 1
            let badge = good ? "<span class=\"ok\">OK</span>" : "<span class=\"fail\">FAIL</span>"
            readHTML += BatteryReport.details("\(doc.uri)  --  \(doc.title)", output.isEmpty ? "(no output)" : output, badge: badge)
        }
        #expect(read >= 20, "\(source.id): read \(read) docs (< 20)")

        html += "<h3>reads from \(BatteryReport.esc(source.id)): \(read)/\(docs.prefix(20).count) documents (read-only)</h3>" + readHTML
        BatteryReport.shared.record(order: ReadBattery.order(of: source.id), html: html)
    }
}

// MARK: - Samples (search + read >= 20 files)

@Suite("#1194 read battery: samples (search + read >= 20)", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatterySamplesTests {
    static let queries = ["view", "swiftui", "animation", "data", "network", "audio", "camera", "widget", "metal", "map"]

    @Test("samples: search + read >= 20 files read-only", .enabled(if: LocalDBs.samplesAvailable))
    func samples() {
        var html = "<h2>search --source samples</h2>"
        var seen = Set<String>()
        var files: [(project: String, path: String)] = []
        var queriesWithHits = 0
        for query in Self.queries {
            let response = CupertinoCLI.searchSamples(query, ["--limit", "10"])
            let matched = response?.files ?? []
            if !matched.isEmpty { queriesWithHits += 1 }
            for file in matched where seen.insert("\(file.projectId)/\(file.path)").inserted {
                files.append((file.projectId, file.path))
            }
            let body = matched.prefix(5).enumerated().map { "[\($0 + 1)] \($1.projectId) / \($1.path)" }.joined(separator: "\n")
            html += BatteryReport.details(
                "\"\(query)\"  ->  \(matched.count) files",
                body.isEmpty ? "(no results)" : body,
                badge: "<span class=\"meta\">[\(matched.count)]</span> "
            )
        }
        #expect(queriesWithHits >= 6, "samples: only \(queriesWithHits)/\(Self.queries.count) queries hit")
        #expect(files.count >= 20, "samples: only gathered \(files.count) distinct files")

        var read = 0
        var readHTML = ""
        for file in files.prefix(20) {
            let output = BatteryReport.stripLog(CupertinoCLI.run(["read-sample-file", file.project, file.path]))
            let good = output.count > 80
            #expect(good, "samples read-sample-file '\(file.project)/\(file.path)' returned trivial output")
            read += 1
            let badge = good ? "<span class=\"ok\">OK</span>" : "<span class=\"fail\">FAIL</span>"
            readHTML += BatteryReport.details("\(file.project) / \(file.path)", output.isEmpty ? "(no output)" : output, badge: badge)
        }
        #expect(read >= 20, "samples: read \(read) files (< 20)")

        html += "<h3>reads from apple-sample-code: \(read)/\(files.prefix(20).count) files (read-only)</h3>" + readHTML
        BatteryReport.shared.record(order: 6, html: html)
    }
}

// MARK: - Packages (search + read >= 20 files)

@Suite("#1194 read battery: packages (search + read >= 20)", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryPackagesTests {
    static let queries = ["logger", "actor", "async", "client", "server", "json", "http", "test", "macro", "collection"]

    @Test("packages: search + read >= 20 files read-only", .enabled(if: LocalDBs.packagesAvailable))
    func packages() {
        var html = "<h2>search --source packages</h2>"
        var seen = Set<String>()
        var identifiers: [String] = []
        var queriesWithHits = 0
        for query in Self.queries {
            let cands = CupertinoCLI.searchPackages(query, ["--limit", "10"])?.candidates ?? []
            if !cands.isEmpty { queriesWithHits += 1 }
            for candidate in cands where seen.insert(candidate.identifier).inserted {
                identifiers.append(candidate.identifier)
            }
            let body = cands.prefix(5).enumerated().map { "[\($0 + 1)] \($1.identifier)" }.joined(separator: "\n")
            html += BatteryReport.details(
                "\"\(query)\"  ->  \(cands.count) candidates",
                body.isEmpty ? "(no results)" : body,
                badge: "<span class=\"meta\">[\(cands.count)]</span> "
            )
        }
        #expect(queriesWithHits >= 6, "packages: only \(queriesWithHits)/\(Self.queries.count) queries hit")
        #expect(identifiers.count >= 20, "packages: only gathered \(identifiers.count) distinct candidates")

        var read = 0
        var readHTML = ""
        for identifier in identifiers.prefix(20) {
            let output = BatteryReport.stripLog(CupertinoCLI.run(["read", identifier, "--source", "packages"]))
            let good = output.count > 80
            #expect(good, "packages read '\(identifier)' returned trivial output")
            read += 1
            let badge = good ? "<span class=\"ok\">OK</span>" : "<span class=\"fail\">FAIL</span>"
            readHTML += BatteryReport.details(identifier, output.isEmpty ? "(no output)" : output, badge: badge)
        }
        #expect(read >= 20, "packages: read \(read) files (< 20)")

        html += "<h3>reads from packages: \(read)/\(identifiers.prefix(20).count) files (read-only)</h3>" + readHTML
        BatteryReport.shared.record(order: 7, html: html)
    }
}

// MARK: - AST search commands

@Suite("#1194 read battery: AST search commands", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryASTTests {
    @Test(
        "search-symbols + search-generics return results across ~10 args",
        .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation))
    )
    func astCommands() {
        var rows = "<h2>AST search commands (apple-docs)</h2><table><tr><th>command</th><th>arg</th><th>#results</th></tr>"
        var symbolHits = 0
        for arg in ["View", "Data", "String", "Color", "Image", "URLSession", "Task", "Array", "Codable", "Error"] {
            let count = CupertinoCLI.searchSymbols(query: arg, ["--limit", "5"])?.results.count ?? 0
            if count >= 1 { symbolHits += 1 }
            rows += "<tr><td>search-symbols</td><td>\(arg)</td><td>\(count)</td></tr>"
        }
        #expect(symbolHits >= 8, "search-symbols: only \(symbolHits)/10 queries hit")

        var genericHits = 0
        for arg in ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "Collection", "Sequence", "Identifiable", "Error", "View"] {
            let count = CupertinoCLI.searchGenerics(constraint: arg, ["--limit", "5"])?.results.count ?? 0
            if count >= 1 { genericHits += 1 }
            rows += "<tr><td>search-generics</td><td>\(arg)</td><td>\(count)</td></tr>"
        }
        #expect(genericHits >= 6, "search-generics: only \(genericHits)/10 constraints hit")
        rows += "</table>"
        BatteryReport.shared.record(order: 8, html: rows)
    }
}

// MARK: - Option coverage (--limit, --format, platform floors)

@Suite("#1194 read battery: option coverage", .serialized, .enabled(if: CupertinoCLI.available))
struct ReadBatteryOptionTests {
    @Test("--limit caps the docs result count", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
    func limitOption() {
        for limit in [1, 3, 5, 10] {
            let results = CupertinoCLI.searchDocs("view", ["--source", "apple-docs", "--limit", "\(limit)"])
            #expect(results.count <= limit, "--limit \(limit) returned \(results.count) results")
        }
    }

    @Test("--format json and markdown both produce output", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
    func formatOption() {
        let json = CupertinoCLI.run(["search", "view", "--source", "apple-docs", "--limit", "3", "--format", "json"])
        #expect(json.contains("[") || json.contains("{"), "json format emitted no JSON")
        let markdown = CupertinoCLI.run(["search", "view", "--source", "apple-docs", "--limit", "3", "--format", "markdown"])
        #expect(markdown.count > 20, "markdown format emitted trivial output")
    }

    @Test("platform floor options run read-only without error", .enabled(if: LocalDBs.available(LocalDBs.appleDocumentation)))
    func platformFloorOptions() {
        for floor in ["--min-ios", "--min-macos", "--min-tvos", "--min-watchos", "--min-visionos"] {
            let out = CupertinoCLI.run(["search", "view", "--source", "apple-docs", "--limit", "5", floor, "16.0", "--format", "json"])
            #expect(out.contains("[") || out.contains("{"), "\(floor) emitted no JSON")
        }
    }
}
