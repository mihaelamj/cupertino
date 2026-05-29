import AppleConstraintsKit
import ArgumentParser
import Foundation
import SearchModels

extension ConstraintsGen.Command {
    /// `cupertino-constraints-gen conformances` subcommand.
    ///
    /// Reads one or more `.symbols.json` files and writes the SDK conformance
    /// table (`apple-conformances.json`) consumed by the conformance enrichment
    /// pass. Conformance sibling of `generate` (which does generic constraints
    /// from the same files); same input modes + same degraded-output guard.
    ///
    /// A type's conformances can be split across the canonical graph and its
    /// cross-module extension files (`SwiftUI@Foundation.symbols.json`), so
    /// entries are MERGED per `docURI` (union of protocol names) rather than
    /// last-write-wins.
    struct Conformances: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "conformances",
            abstract: "Parse symbol-graph JSON file(s) and emit the cupertino conformance table (apple-conformances.json)."
        )

        @Argument(help: "Explicit list of .symbols.json files. Empty when --from-directory is set.")
        var symbolGraphFiles: [String] = []

        @Option(name: .long, help: "Recursively scan a directory for *.symbols.json files. Mutually exclusive with positional args.")
        var fromDirectory: String?

        @Option(name: .shortAndLong, help: "Output JSON path for the conformance table.")
        var output: String

        @Flag(name: .long, help: "Print per-file entry counts as files are processed.")
        var verbose: Bool = false

        mutating func run() async throws {
            let inputURLs = try resolveInputURLs()

            var conformsByURI: [String: [String]] = [:]
            var uriOrder: [String] = []
            var unreadable: [String] = []
            var unparseable: [String] = []

            for url in inputURLs {
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    unreadable.append(url.lastPathComponent)
                    if verbose {
                        FileHandle.standardError.write(Data("⚠ skipping unreadable file \(url.path): \(error)\n".utf8))
                    }
                    continue
                }

                let entries: [Search.StaticConformanceEntry]
                do {
                    entries = try AppleConstraintsKit.ConformanceExtractor.extractEntries(from: data)
                } catch {
                    unparseable.append(url.lastPathComponent)
                    if verbose {
                        FileHandle.standardError.write(Data("⚠ skipping unparseable file \(url.path): \(error)\n".utf8))
                    }
                    continue
                }

                Self.merge(entries, into: &conformsByURI, order: &uriOrder)

                if verbose {
                    FileHandle.standardError.write(Data("✓ \(url.lastPathComponent): \(entries.count) conforming types\n".utf8))
                }
            }

            let merged = uriOrder
                .map { Search.StaticConformanceEntry(docURI: $0, conformsTo: conformsByURI[$0] ?? []) }
                .sorted { $0.docURI < $1.docURI }

            // Refuse to emit a degraded table, mirroring `generate`. A 0-entry
            // apple-conformances.json would silently strip the SDK conformance
            // enrichment from apple-docs, visible only by inspecting the DB.
            guard !merged.isEmpty else {
                throw Error.noConformancesExtracted(
                    inputCount: inputURLs.count,
                    unreadable: unreadable,
                    unparseable: unparseable
                )
            }

            let table = AppleConstraintsKit.ConformanceTable(entries: merged)
            let jsonData = try table.jsonData()
            let outputURL = URL(fileURLWithPath: output)
            try jsonData.write(to: outputURL)

            print("Wrote \(merged.count) conformance entries to \(outputURL.path) (\(jsonData.count) bytes).")
        }

        /// Merge one file's entries into the accumulators: union the protocol
        /// names per conforming-type URI, preserving first-seen URI order.
        private static func merge(
            _ entries: [Search.StaticConformanceEntry],
            into conformsByURI: inout [String: [String]],
            order: inout [String]
        ) {
            for entry in entries {
                if conformsByURI[entry.docURI] == nil {
                    order.append(entry.docURI)
                }
                for name in entry.conformsTo where !(conformsByURI[entry.docURI]?.contains(name) ?? false) {
                    conformsByURI[entry.docURI, default: []].append(name)
                }
            }
        }

        private func resolveInputURLs() throws -> [URL] {
            switch (symbolGraphFiles.isEmpty, fromDirectory) {
            case (true, .some(let dir)):
                let dirURL = URL(fileURLWithPath: dir)
                let hits = try scanDirectory(dirURL)
                guard !hits.isEmpty else {
                    throw Error.emptySymbolGraphDirectory(path: dirURL.path)
                }
                return hits
            case (false, .none):
                return symbolGraphFiles.map { URL(fileURLWithPath: $0) }
            case (false, .some):
                throw Error.conflictingInputs
            case (true, .none):
                throw Error.noInputs
            }
        }

        private func scanDirectory(_ directory: URL) throws -> [URL] {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            var hits: [URL] = []
            for case let url as URL in enumerator
                where url.lastPathComponent.hasSuffix(".symbols.json") {
                hits.append(url)
            }
            return hits.sorted { $0.path < $1.path }
        }

        enum Error: Swift.Error, CustomStringConvertible {
            case noInputs
            case conflictingInputs
            case emptySymbolGraphDirectory(path: String)
            case noConformancesExtracted(inputCount: Int, unreadable: [String], unparseable: [String])

            var description: String {
                switch self {
                case .noInputs:
                    return "No input files provided. Pass either positional .symbols.json paths OR --from-directory."
                case .conflictingInputs:
                    return "Cannot mix positional file list with --from-directory; pick one."
                case .emptySymbolGraphDirectory(let path):
                    return Self.help(lead: "No *.symbols.json files found under \(path).")
                case .noConformancesExtracted(let inputCount, let unreadable, let unparseable):
                    var lead = "Read \(inputCount) input file(s) but extracted 0 conformances"
                    if !unreadable.isEmpty {
                        lead += "; unreadable: \(unreadable.joined(separator: ", "))"
                    }
                    if !unparseable.isEmpty {
                        lead += "; unparseable: \(unparseable.joined(separator: ", "))"
                    }
                    lead += "."
                    return Self.help(lead: lead)
                }
            }

            private static func help(lead: String) -> String {
                """
                \(lead)
                apple-conformances.json must NOT be written from an empty or degraded symbol-graph set.
                apple-docs would otherwise silently lose the SDK conformance graph (the conformances DocC markdown omits).
                Produce symbol graphs, then re-run:
                  swift symbolgraph-extract -module-name <Framework> -target <triple> \\
                    -sdk "$(xcrun --show-sdk-path)" -output-dir <dir>
                  cupertino-constraints-gen conformances --from-directory <dir> -o apple-conformances.json
                The cupertino-symbolgraphs corpus is the canonical home for these *.symbols.json files.
                """
            }
        }
    }
}
