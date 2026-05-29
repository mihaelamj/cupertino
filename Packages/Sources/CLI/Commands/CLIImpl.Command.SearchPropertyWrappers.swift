import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants

// MARK: - search-property-wrappers Command (#948 phase 2)

/// CLI command for `search_property_wrappers` (MCP). Phase 2 of
/// #948; follows the pattern set by `search-symbols` (phase 1).
/// Calls `Search.Index.searchPropertyWrappers` directly; inherits
/// the canonical-framework-boost from #952.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct SearchPropertyWrappers: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search-property-wrappers",
            abstract: "Find symbols whose declaration uses a given property wrapper",
            discussion: """
            Mirrors the `search_property_wrappers` MCP tool. Returns symbols
            whose `attributes` column contains the queried `@Wrapper` token.
            Common wrappers: @State, @Binding, @Observable, @MainActor,
            @Published, @Model, @Query. Pass the wrapper name with or
            without the leading `@`.

            EXAMPLES:
              cupertino search-property-wrappers --wrapper State
              cupertino search-property-wrappers --wrapper "@Observable" --limit 5
              cupertino search-property-wrappers --wrapper MainActor --framework uikit
              cupertino search-property-wrappers --wrapper Published --format json | jq

            RANKING:
              Inherits #952 canonical-framework boost: rows in the
              wrapper's canonical-usage framework set rank above all
              others. Unknown wrappers fall through to the operator-
              demote + kind-shape tiers of the shared
              signalRankOrderClause.
            """
        )

        @Option(
            name: .long,
            help: "Property wrapper name (with or without @). Required."
        )
        var wrapper: String

        @Option(
            name: .long,
            help: "Restrict to a single framework (e.g. swiftui, uikit, combine)"
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
            guard !wrapper.isEmpty else {
                CLIImpl.printUserFacingDiagnostic("❌ --wrapper must be non-empty", recording: recording)
                throw ExitCode.failure
            }

            let dbURLs = try CLIImpl.resolveSymbolSearchDBURLs(searcher: .propertyWrappers, source: source, baseDir: baseDir)
            guard !dbURLs.isEmpty else {
                CLIImpl.printUserFacingDiagnostic(
                    "❌ No symbol-bearing database found. Run `cupertino setup` or `cupertino save` first.",
                    recording: recording
                )
                throw ExitCode.failure
            }

            let results = try await CLIImpl.fanOutSymbolSearch(dbURLs: dbURLs, logger: recording, limit: limit) { index in
                let raw = try await index.searchPropertyWrappers(
                    wrapper: wrapper,
                    framework: framework,
                    limit: limit
                )
                return try await index.applyingPlatformFloors(to: raw, floors: platformFloors.floors())
            }

            let normalizedWrapper = wrapper.hasPrefix("@") ? wrapper : "@\(wrapper)"

            switch format {
            case .text:
                emitText(results: results, wrapper: normalizedWrapper)
            case .json:
                try emitJSON(results: results, wrapper: normalizedWrapper)
            case .markdown:
                emitMarkdown(results: results, wrapper: normalizedWrapper)
            }
        }

        // MARK: - Output

        private var filterSummary: String {
            var parts = ["wrapper=\(wrapper)"]
            if let framework, !framework.isEmpty { parts.append("framework=\(framework)") }
            return parts.joined(separator: ", ")
        }

        private func emitText(results: [SearchModels.Search.SymbolSearchResult], wrapper: String) {
            let recording = Cupertino.Context.composition.logging.recording
            guard !results.isEmpty else {
                recording.output("No symbols match \(wrapper). Filters: \(filterSummary)")
                return
            }
            var out = "Found \(results.count) symbol\(results.count == 1 ? "" : "s") with \(wrapper) (\(filterSummary)):\n"
            for result in results {
                out += "  \(result.symbolKind) \(result.symbolName)"
                if result.isAsync { out += " async" }
                out += "  [\(result.framework.isEmpty ? "?" : result.framework)] \(result.docUri)\n"
                if let attrs = result.attributes, !attrs.isEmpty {
                    out += "    attributes: \(attrs)\n"
                }
            }
            recording.output(out)
        }

        private func emitMarkdown(results: [SearchModels.Search.SymbolSearchResult], wrapper: String) {
            var out = "# Property Wrapper: \(wrapper)\n\n"
            out += "**Filters:** \(filterSummary)\n\n"
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
                }
                out += "\n"
            }
            Cupertino.Context.composition.logging.recording.output(out)
        }

        private func emitJSON(results: [SearchModels.Search.SymbolSearchResult], wrapper: String) throws {
            let payload = JSONPayload(
                filters: JSONFilters(
                    wrapper: wrapper,
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

extension CLIImpl.Command.SearchPropertyWrappers {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown

        init?(argument: String) {
            self.init(rawValue: CLIImpl.Command.OutputFormatArgument.normalize(argument))
        }
    }

    private struct JSONFilters: Codable {
        let wrapper: String
        let framework: String?
        let limit: Int
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
            isAsync = result.isAsync
            isPublic = result.isPublic
        }
    }

    private struct JSONPayload: Codable {
        let filters: JSONFilters
        let results: [JSONSymbol]
    }
}
