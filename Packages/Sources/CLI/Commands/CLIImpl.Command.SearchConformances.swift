import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants

// MARK: - search-conformances Command (#948 phase 4)

/// CLI command for `search_conformances` (MCP). Phase 4 of #948.
/// Returns symbols that conform to a given protocol (e.g. View,
/// Codable, Hashable, Sendable).
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct SearchConformances: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search-conformances",
            abstract: "Find symbols that conform to a given protocol",
            discussion: """
            Mirrors the `search_conformances` MCP tool. Matches against the
            `conformances` column populated at index time from each symbol's
            `relationshipsSections` block.

            EXAMPLES:
              cupertino search-conformances --protocol View
              cupertino search-conformances --protocol Codable --framework foundation
              cupertino search-conformances --protocol Hashable --limit 20
              cupertino search-conformances --protocol Sendable --format json | jq
            """
        )

        @Option(
            name: .customLong("protocol"),
            help: "Protocol name to find conformers of (e.g. View, Codable, Hashable, Sendable). Required."
        )
        var protocolName: String

        @Option(
            name: .long,
            help: "Restrict to a single framework (e.g. swiftui, foundation)"
        )
        var framework: String?

        @Option(
            name: .long,
            help: "Maximum results (default \(Shared.Constants.Limit.defaultSearchLimit))"
        )
        var limit: Int = Shared.Constants.Limit.defaultSearchLimit

        @Option(
            name: .long,
            help: "Output format: text (default), json, markdown"
        )
        var format: OutputFormat = .text

        @Option(
            name: .long,
            help: CLIImpl.appleDocsDBOverrideHelp
        )
        var searchDb: String?

        mutating func run() async throws {
            let recording = Cupertino.Context.composition.logging.recording
            guard limit > 0 else {
                CLIImpl.printUserFacingDiagnostic("❌ --limit must be at least 1", recording: recording)
                throw ExitCode.failure
            }
            guard !protocolName.isEmpty else {
                CLIImpl.printUserFacingDiagnostic("❌ --protocol must be non-empty", recording: recording)
                throw ExitCode.failure
            }

            let searchDBURL = CLIImpl.resolveAppleDocsDBURL(override: searchDb)
            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                CLIImpl.printUserFacingDiagnostic(
                    CLIImpl.appleDocsDBMissingMessage(url: searchDBURL),
                    recording: recording
                )
                throw ExitCode.failure
            }

            let index = try await SearchModule.Index(
                dbPath: searchDBURL,
                logger: recording,
                indexers: [:],
                sourceLookup: .empty
            )
            defer { Task { await index.disconnect() } }

            let results = try await index.searchConformances(
                protocolName: protocolName,
                framework: framework,
                limit: limit
            )

            switch format {
            case .text:
                emitText(results: results)
            case .json:
                try emitJSON(results: results)
            case .markdown:
                emitMarkdown(results: results)
            }
        }

        private var filterSummary: String {
            var parts = ["protocol=\(protocolName)"]
            if let framework, !framework.isEmpty { parts.append("framework=\(framework)") }
            return parts.joined(separator: ", ")
        }

        private func emitText(results: [SearchModels.Search.SymbolSearchResult]) {
            let recording = Cupertino.Context.composition.logging.recording
            guard !results.isEmpty else {
                recording.output("No symbols conform to \(protocolName). Filters: \(filterSummary)")
                return
            }
            var out = "Found \(results.count) symbol\(results.count == 1 ? "" : "s") conforming to \(protocolName) (\(filterSummary)):\n"
            for result in results {
                out += "  \(result.symbolKind) \(result.symbolName)"
                out += "  [\(result.framework.isEmpty ? "?" : result.framework)] \(result.docUri)\n"
                if let conforms = result.conformances, !conforms.isEmpty {
                    out += "    conforms to: \(conforms)\n"
                }
            }
            recording.output(out)
        }

        private func emitMarkdown(results: [SearchModels.Search.SymbolSearchResult]) {
            var out = "# Conformances: \(protocolName)\n\n**Filters:** \(filterSummary)\n\n"
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
                out += "### \(first.docTitle)\n_Framework: \(first.framework.isEmpty ? "unknown" : first.framework)_ | URI: `\(uri)`\n\n"
                for sym in symbols {
                    out += "- **\(sym.symbolKind)** `\(sym.symbolName)`\n"
                    if let conforms = sym.conformances, !conforms.isEmpty {
                        out += "  - Conforms to: \(conforms)\n"
                    }
                }
                out += "\n"
            }
            Cupertino.Context.composition.logging.recording.output(out)
        }

        private func emitJSON(results: [SearchModels.Search.SymbolSearchResult]) throws {
            let payload = JSONPayload(
                filters: JSONFilters(protocolName: protocolName, framework: framework, limit: limit),
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

extension CLIImpl.Command.SearchConformances {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }

    private struct JSONFilters: Codable {
        let protocolName: String
        let framework: String?
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case protocolName = "protocol"
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
        let conformances: String?
        let isPublic: Bool

        enum CodingKeys: String, CodingKey {
            case docUri = "doc_uri"
            case docTitle = "doc_title"
            case framework
            case symbolName = "symbol_name"
            case symbolKind = "symbol_kind"
            case conformances
            case isPublic = "is_public"
        }

        init(_ result: SearchModels.Search.SymbolSearchResult) {
            docUri = result.docUri
            docTitle = result.docTitle
            framework = result.framework
            symbolName = result.symbolName
            symbolKind = result.symbolKind
            conformances = result.conformances
            isPublic = result.isPublic
        }
    }

    private struct JSONPayload: Codable {
        let filters: JSONFilters
        let results: [JSONSymbol]
    }
}
