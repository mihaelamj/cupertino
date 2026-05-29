import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants

// MARK: - search-symbols Command (#948)

/// CLI command for `search_symbols` (MCP). Pre-#948 the 5 AST tools
/// (`search_symbols`, `search_property_wrappers`, `search_concurrency`,
/// `search_conformances`, `search_generics`) were MCP-only; reaching
/// them from the shell required wiring up `cupertino serve` over
/// stdio and speaking JSON-RPC. #948 surfaces each as a CLI sibling
/// with the same parameter set + an `--format` flag.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct SearchSymbols: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search-symbols",
            abstract: "Search indexed AST symbols by name + kind + async + framework",
            discussion: """
            Mirrors the `search_symbols` MCP tool. Returns symbols matching
            the optional name substring + kind + async filter + framework.

            EXAMPLES:
              cupertino search-symbols --query Task --kind struct
              cupertino search-symbols --kind protocol --framework swiftui
              cupertino search-symbols --is-async --limit 20
              cupertino search-symbols --query View --kind protocol --format json | jq

            KINDS:
              class, struct, enum, protocol, actor, typealias, macro,
              method, function, property, initializer, subscript, case, operator
            """
        )

        @Option(
            name: .long,
            help: "Substring to match against symbol name (case-insensitive). Omit for kind/async-only queries."
        )
        var query: String?

        @Option(
            name: .long,
            help: "Restrict to a single kind (class, struct, enum, protocol, actor, method, function, property, ...)"
        )
        var kind: String?

        @Flag(
            name: .long,
            help: "Only match symbols marked `async`"
        )
        var isAsync: Bool = false

        @Option(
            name: .long,
            help: "Restrict to a single framework (e.g. swiftui, uikit, foundation)"
        )
        var framework: String?

        @Option(
            name: .long,
            help: "Maximum results (default \(Shared.Constants.Limit.defaultSearchLimit))"
        )
        var limit: Int = Shared.Constants.Limit.defaultSearchLimit

        @Option(
            name: .long,
            help: CLIImpl.Command.OutputFormatArgument.textDefaultHelp
        )
        var format: OutputFormat = .text

        @Option(
            name: .long,
            help: "Directory holding the per-source DBs. Defaults to the configured base directory."
        )
        var baseDir: String?

        @Option(
            name: .long,
            help: "Restrict to one source id (e.g. apple-docs, swift-org, swift-book). Default: every source whose DB carries indexed symbols."
        )
        var source: String?

        @OptionGroup var platformFloors: CLIImpl.PlatformFloorOptions

        mutating func run() async throws {
            let recording = Cupertino.Context.composition.logging.recording
            guard limit > 0 else {
                CLIImpl.printUserFacingDiagnostic("❌ --limit must be at least 1", recording: recording)
                throw ExitCode.failure
            }

            let dbURLs = try CLIImpl.resolveSymbolSearchDBURLs(searcher: .symbols, source: source, baseDir: baseDir)
            guard !dbURLs.isEmpty else {
                CLIImpl.printUserFacingDiagnostic(
                    "❌ No symbol-bearing database found. Run `cupertino setup` or `cupertino save` first.",
                    recording: recording
                )
                throw ExitCode.failure
            }

            let results = await CLIImpl.fanOutSymbolSearch(dbURLs: dbURLs, logger: recording, limit: limit) { index in
                let raw = try await index.searchSymbols(
                    query: query,
                    kind: kind,
                    isAsync: isAsync ? true : nil,
                    framework: framework,
                    limit: limit
                )
                return try await index.applyingPlatformFloors(to: raw, floors: platformFloors.floors())
            }

            switch format {
            case .text:
                emitText(results: results)
            case .json:
                try emitJSON(results: results)
            case .markdown:
                emitMarkdown(results: results)
            }
        }

        // MARK: - Output

        private var filterSummary: String {
            var parts: [String] = []
            if let query, !query.isEmpty { parts.append("query=\(query)") }
            if let kind, !kind.isEmpty { parts.append("kind=\(kind)") }
            if isAsync { parts.append("is_async=true") }
            if let framework, !framework.isEmpty { parts.append("framework=\(framework)") }
            return parts.joined(separator: ", ")
        }

        private func emitText(results: [SearchModels.Search.SymbolSearchResult]) {
            let recording = Cupertino.Context.composition.logging.recording
            guard !results.isEmpty else {
                recording.output("No symbols matched. Filters: \(filterSummary.isEmpty ? "(none)" : filterSummary)")
                return
            }
            var out = "Found \(results.count) symbol\(results.count == 1 ? "" : "s") (\(filterSummary)):\n"
            for result in results {
                out += "  \(result.symbolKind) \(result.symbolName)"
                if result.isAsync { out += " async" }
                out += "  [\(result.framework.isEmpty ? "?" : result.framework)] \(result.docUri)\n"
                if let sig = result.signature, !sig.isEmpty {
                    let truncated = sig.count > 80 ? String(sig.prefix(80)) + "..." : sig
                    out += "    signature: \(truncated)\n"
                }
                if let attrs = result.attributes, !attrs.isEmpty {
                    out += "    attributes: \(attrs)\n"
                }
                if let conforms = result.conformances, !conforms.isEmpty {
                    out += "    conforms to: \(conforms)\n"
                }
            }
            recording.output(out)
        }

        private func emitMarkdown(results: [SearchModels.Search.SymbolSearchResult]) {
            var out = "# Symbol Search Results\n\n"
            if !filterSummary.isEmpty {
                out += "**Filters:** \(filterSummary)\n\n"
            }
            if results.isEmpty {
                out += "_No symbols matched._\n"
                Cupertino.Context.composition.logging.recording.output(out)
                return
            }
            out += "Found **\(results.count)** symbols:\n\n"
            var byDoc: [String: [SearchModels.Search.SymbolSearchResult]] = [:]
            for symbol in results {
                byDoc[symbol.docUri, default: []].append(symbol)
            }
            for (uri, symbols) in byDoc.sorted(by: { $0.key < $1.key }) {
                let first = symbols[0]
                out += "### \(first.docTitle)\n"
                out += "_Framework: \(first.framework.isEmpty ? "unknown" : first.framework)_ | URI: `\(uri)`\n\n"
                for sym in symbols {
                    out += "- **\(sym.symbolKind)** `\(sym.symbolName)`"
                    if sym.isAsync { out += " `async`" }
                    out += "\n"
                    if let attrs = sym.attributes, !attrs.isEmpty {
                        out += "  - Attributes: \(attrs)\n"
                    }
                    if let conforms = sym.conformances, !conforms.isEmpty {
                        out += "  - Conforms to: \(conforms)\n"
                    }
                    if let generics = sym.genericParams, !generics.isEmpty {
                        out += "  - Generic params: `\(generics)`\n"
                    }
                }
                out += "\n"
            }
            Cupertino.Context.composition.logging.recording.output(out)
        }

        private func emitJSON(results: [SearchModels.Search.SymbolSearchResult]) throws {
            let payload = JSONPayload(
                filters: JSONFilters(
                    query: query,
                    kind: kind,
                    isAsync: isAsync ? true : nil,
                    framework: framework,
                    limit: limit
                ),
                results: results.map(JSONSymbol.init)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(payload)
            if let string = String(data: data, encoding: .utf8) {
                Cupertino.Context.composition.logging.recording.output(string)
            }
        }
    }
}

// MARK: - Option / JSON types

extension CLIImpl.Command.SearchSymbols {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown

        init?(argument: String) {
            self.init(rawValue: CLIImpl.Command.OutputFormatArgument.normalize(argument))
        }
    }

    private struct JSONFilters: Codable {
        let query: String?
        let kind: String?
        let isAsync: Bool?
        let framework: String?
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case query
            case kind
            case isAsync = "is_async"
            case framework
            case limit
        }
    }

    private struct JSONSymbol: Codable {
        let docUri: String
        let docTitle: String
        let framework: String
        let symbolName: String
        let symbolKind: String
        let signature: String?
        let attributes: String?
        let conformances: String?
        let genericParams: String?
        let isAsync: Bool
        let isPublic: Bool

        enum CodingKeys: String, CodingKey {
            case docUri = "doc_uri"
            case docTitle = "doc_title"
            case framework
            case symbolName = "symbol_name"
            case symbolKind = "symbol_kind"
            case signature
            case attributes
            case conformances
            case genericParams = "generic_params"
            case isAsync = "is_async"
            case isPublic = "is_public"
        }

        init(_ result: SearchModels.Search.SymbolSearchResult) {
            docUri = result.docUri
            docTitle = result.docTitle
            framework = result.framework
            symbolName = result.symbolName
            symbolKind = result.symbolKind
            signature = result.signature
            attributes = result.attributes
            conformances = result.conformances
            genericParams = result.genericParams
            isAsync = result.isAsync
            isPublic = result.isPublic
        }
    }

    private struct JSONPayload: Codable {
        let filters: JSONFilters
        let results: [JSONSymbol]
    }
}
