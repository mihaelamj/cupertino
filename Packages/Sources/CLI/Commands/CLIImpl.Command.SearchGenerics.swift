import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants

// MARK: - search-generics Command (#948 phase 5)

/// CLI command for `search_generics` (MCP). Phase 5 of #948.
/// Returns symbols whose generic-parameter list includes the
/// queried constraint (e.g. `T: View`, `T: Hashable & Sendable`).
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct SearchGenerics: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search-generics",
            abstract: "Find symbols with a generic-parameter constraint",
            discussion: """
            Mirrors the `search_generics` MCP tool. Matches against the
            `generic_constraints` column populated at index time by the
            AST extractor (#755 / #759); accepts both inline `<T: Foo>`
            form and where-clause `where T: Foo` form.

            EXAMPLES:
              cupertino search-generics --constraint View
              cupertino search-generics --constraint Hashable --framework swift
              cupertino search-generics --constraint Sendable --limit 20
              cupertino search-generics --constraint Codable --format json | jq
            """
        )

        @Option(
            name: .long,
            help: "Generic constraint type (e.g. View, Hashable, Sendable, Codable). Required."
        )
        var constraint: String

        @Option(
            name: .long,
            help: "Restrict to a single framework (e.g. swiftui, swift)"
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
            help: "Path to search database"
        )
        var searchDb: String?

        mutating func run() async throws {
            let recording = Cupertino.Context.composition.logging.recording
            guard limit > 0 else {
                CLIImpl.printUserFacingDiagnostic("❌ --limit must be at least 1", recording: recording)
                throw ExitCode.failure
            }
            guard !constraint.isEmpty else {
                CLIImpl.printUserFacingDiagnostic("❌ --constraint must be non-empty", recording: recording)
                throw ExitCode.failure
            }

            let searchDBURL = searchDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Paths.live().searchDatabase
            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                CLIImpl.printUserFacingDiagnostic(
                    "❌ search.db not found at \(searchDBURL.path). Run `cupertino setup` first.",
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

            let results = try await index.searchByGenericConstraint(
                constraint: constraint,
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
            var parts = ["constraint=\(constraint)"]
            if let framework, !framework.isEmpty { parts.append("framework=\(framework)") }
            return parts.joined(separator: ", ")
        }

        private func emitText(results: [SearchModels.Search.SymbolSearchResult]) {
            let recording = Cupertino.Context.composition.logging.recording
            guard !results.isEmpty else {
                recording.output("No symbols constrained by \(constraint). Filters: \(filterSummary)")
                return
            }
            var out = "Found \(results.count) symbol\(results.count == 1 ? "" : "s") with constraint \(constraint) (\(filterSummary)):\n"
            for result in results {
                out += "  \(result.symbolKind) \(result.symbolName)"
                out += "  [\(result.framework.isEmpty ? "?" : result.framework)] \(result.docUri)\n"
                if let generics = result.genericParams, !generics.isEmpty {
                    out += "    generic params: \(generics)\n"
                }
            }
            recording.output(out)
        }

        private func emitMarkdown(results: [SearchModels.Search.SymbolSearchResult]) {
            var out = "# Generic Constraint: \(constraint)\n\n**Filters:** \(filterSummary)\n\n"
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
                filters: JSONFilters(constraint: constraint, framework: framework, limit: limit),
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

extension CLIImpl.Command.SearchGenerics {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }

    private struct JSONFilters: Codable {
        let constraint: String
        let framework: String?
        let limit: Int
    }

    private struct JSONSymbol: Codable {
        let docUri: String
        let docTitle: String
        let framework: String
        let symbolName: String
        let symbolKind: String
        let genericParams: String?
        let isPublic: Bool

        enum CodingKeys: String, CodingKey {
            case docUri = "doc_uri"
            case docTitle = "doc_title"
            case framework
            case symbolName = "symbol_name"
            case symbolKind = "symbol_kind"
            case genericParams = "generic_params"
            case isPublic = "is_public"
        }

        init(_ result: SearchModels.Search.SymbolSearchResult) {
            docUri = result.docUri
            docTitle = result.docTitle
            framework = result.framework
            symbolName = result.symbolName
            symbolKind = result.symbolKind
            genericParams = result.genericParams
            isPublic = result.isPublic
        }
    }

    private struct JSONPayload: Codable {
        let filters: JSONFilters
        let results: [JSONSymbol]
    }
}
