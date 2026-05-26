import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SearchAPI
import SearchModels
import SharedConstants

// MARK: - search-concurrency Command (#948 phase 3)

/// CLI command for `search_concurrency` (MCP). Phase 3 of #948.
/// Returns symbols matching a Swift concurrency pattern keyword
/// (`async`, `actor`, `sendable`, `mainactor`, `task`, etc.).
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct SearchConcurrency: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search-concurrency",
            abstract: "Find symbols using a Swift concurrency pattern (async / actor / sendable / mainactor / task)",
            discussion: """
            Mirrors the `search_concurrency` MCP tool. The `--pattern` value
            is matched against attribute, conformance, and signature columns
            to surface symbols that exhibit the queried concurrency idiom.

            EXAMPLES:
              cupertino search-concurrency --pattern async
              cupertino search-concurrency --pattern actor --framework swiftui
              cupertino search-concurrency --pattern sendable --limit 20
              cupertino search-concurrency --pattern mainactor --format json | jq
            """
        )

        @Option(
            name: .long,
            help: "Concurrency pattern: async, actor, sendable, mainactor, task, asyncsequence. Required."
        )
        var pattern: String

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
            guard !pattern.isEmpty else {
                CLIImpl.printUserFacingDiagnostic("❌ --pattern must be non-empty", recording: recording)
                throw ExitCode.failure
            }

            let searchDBURL = CLIImpl.resolveAppleDocsDBURL(override: searchDb)
            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                CLIImpl.printUserFacingDiagnostic(
                    CLIImpl.perSourceDBMissingMessage(url: searchDBURL),
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

            let results = try await index.searchConcurrencyPatterns(
                pattern: pattern,
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
            var parts = ["pattern=\(pattern)"]
            if let framework, !framework.isEmpty { parts.append("framework=\(framework)") }
            return parts.joined(separator: ", ")
        }

        private func emitText(results: [SearchModels.Search.SymbolSearchResult]) {
            let recording = Cupertino.Context.composition.logging.recording
            guard !results.isEmpty else {
                recording.output("No symbols match pattern=\(pattern). Filters: \(filterSummary)")
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
            }
            recording.output(out)
        }

        private func emitMarkdown(results: [SearchModels.Search.SymbolSearchResult]) {
            var out = "# Concurrency Pattern: \(pattern)\n\n**Filters:** \(filterSummary)\n\n"
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
                    out += "- **\(sym.symbolKind)** `\(sym.symbolName)`"
                    if sym.isAsync { out += " `async`" }
                    out += "\n"
                }
                out += "\n"
            }
            Cupertino.Context.composition.logging.recording.output(out)
        }

        private func emitJSON(results: [SearchModels.Search.SymbolSearchResult]) throws {
            let payload = JSONPayload(
                filters: JSONFilters(pattern: pattern, framework: framework, limit: limit),
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

extension CLIImpl.Command.SearchConcurrency {
    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }

    private struct JSONFilters: Codable {
        let pattern: String
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
