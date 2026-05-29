import AppleConstraintsKit
import ArgumentParser
import Foundation
import SearchModels

extension ConstraintsGen.Command {
    /// `cupertino-constraints-gen generate` subcommand.
    ///
    /// Reads one or more `.symbols.json` files (output of
    /// `swift symbolgraph-extract`) and writes the filtered constraint
    /// table to a target JSON path.
    ///
    /// **Two input modes.**
    /// 1. Explicit file list via positional args:
    ///    `cupertino-constraints-gen generate /path/to/SwiftUI.symbols.json
    ///    /path/to/Foundation.symbols.json -o apple-constraints.json`
    /// 2. Recursive directory scan via `--from-directory`:
    ///    `cupertino-constraints-gen generate --from-directory
    ///    /tmp/symbolgraphs -o apple-constraints.json`. Picks up every
    ///    `*.symbols.json` under the directory, including cross-module
    ///    extension files (`SwiftUI@Foundation.symbols.json` etc.).
    ///
    /// **Deduplication.** Multiple input files can emit entries for
    /// the same `docURI` (rare for one SDK version but possible across
    /// extension files). The output keeps the LAST entry per URI;
    /// callers wanting different precedence should pass files in the
    /// desired override order.
    struct Generate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "generate",
            abstract: "Parse symbol-graph JSON file(s) and emit the cupertino constraints table."
        )

        @Argument(help: "Explicit list of .symbols.json files. Empty when --from-directory is set.")
        var symbolGraphFiles: [String] = []

        @Option(name: .long, help: "Recursively scan a directory for *.symbols.json files. Mutually exclusive with positional args.")
        var fromDirectory: String?

        @Option(name: .shortAndLong, help: "Output JSON path for the filtered constraints table.")
        var output: String

        @Flag(name: .long, help: "Print per-file entry counts as files are processed.")
        var verbose: Bool = false

        mutating func run() async throws {
            let inputURLs = try resolveInputURLs()

            var byURI: [String: [String]] = [:]
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

                let entries: [Search.StaticConstraintEntry]
                do {
                    entries = try AppleConstraintsKit.Extractor.extractEntries(from: data)
                } catch {
                    unparseable.append(url.lastPathComponent)
                    if verbose {
                        FileHandle.standardError.write(Data("⚠ skipping unparseable file \(url.path): \(error)\n".utf8))
                    }
                    continue
                }

                for entry in entries {
                    byURI[entry.docURI] = entry.constraints
                }

                if verbose {
                    FileHandle.standardError.write(Data("✓ \(url.lastPathComponent): \(entries.count) entries\n".utf8))
                }
            }

            let merged = byURI
                .map { Search.StaticConstraintEntry(docURI: $0.key, constraints: $0.value) }
                .sorted { $0.docURI < $1.docURI }

            // Refuse to emit a degraded table. A 0-entry apple-constraints.json
            // silently strips Apple generic-constraint enrichment from every
            // consuming DB (apple-docs, samples, packages), and the loss is only
            // visible by inspecting the DB afterwards. Hard-fail with the fix.
            guard !merged.isEmpty else {
                throw GenerateError.noConstraintsExtracted(
                    inputCount: inputURLs.count,
                    unreadable: unreadable,
                    unparseable: unparseable
                )
            }

            let table = AppleConstraintsKit.Table(entries: merged)
            let jsonData = try table.jsonData()

            let outputURL = URL(fileURLWithPath: output)
            // Atomic write (temp + rename) so a `cupertino save` reading this
            // file at its enrichment phase WHILE this generator runs sees the
            // complete old or complete new table, never a half-written one.
            try jsonData.write(to: outputURL, options: .atomic)

            print("Wrote \(merged.count) entries to \(outputURL.path) (\(jsonData.count) bytes).")
        }

        private func resolveInputURLs() throws -> [URL] {
            switch (symbolGraphFiles.isEmpty, fromDirectory) {
            case (true, .some(let dir)):
                let dirURL = URL(fileURLWithPath: dir)
                let hits = try scanDirectory(dirURL)
                // Directory resolved but holds no symbol graphs (e.g. an empty
                // cupertino-symbolgraphs checkout). Name the fix rather than
                // the generic "no inputs" message.
                guard !hits.isEmpty else {
                    throw GenerateError.emptySymbolGraphDirectory(path: dirURL.path)
                }
                return hits
            case (false, .none):
                return symbolGraphFiles.map { URL(fileURLWithPath: $0) }
            case (false, .some):
                throw GenerateError.conflictingInputs
            case (true, .none):
                throw GenerateError.noInputs
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

        enum GenerateError: Swift.Error, CustomStringConvertible {
            case noInputs
            case conflictingInputs
            case emptySymbolGraphDirectory(path: String)
            case noConstraintsExtracted(inputCount: Int, unreadable: [String], unparseable: [String])

            var description: String {
                switch self {
                case .noInputs:
                    return "No input files provided. Pass either positional .symbols.json paths OR --from-directory."
                case .conflictingInputs:
                    return "Cannot mix positional file list with --from-directory; pick one."
                case .emptySymbolGraphDirectory(let path):
                    return Self.symbolGraphHelp(lead: "No *.symbols.json files found under \(path).")
                case .noConstraintsExtracted(let inputCount, let unreadable, let unparseable):
                    var lead = "Read \(inputCount) input file(s) but extracted 0 constraints"
                    if !unreadable.isEmpty {
                        lead += "; unreadable: \(unreadable.joined(separator: ", "))"
                    }
                    if !unparseable.isEmpty {
                        lead += "; unparseable: \(unparseable.joined(separator: ", "))"
                    }
                    lead += "."
                    return Self.symbolGraphHelp(lead: lead)
                }
            }

            /// Shared remediation text for the two "no usable symbol graphs"
            /// failures. Names the producer command so the operator can
            /// recover without reading the source.
            private static func symbolGraphHelp(lead: String) -> String {
                """
                \(lead)
                apple-constraints.json must NOT be written from an empty or degraded symbol-graph set.
                Every consuming DB (apple-docs, samples, packages) would otherwise silently lose its Apple generic-constraint enrichment.
                Produce symbol graphs, then re-run:
                  swift symbolgraph-extract -module-name <Framework> -target <triple> \\
                    -sdk "$(xcrun --show-sdk-path)" -output-dir <dir>
                  cupertino-constraints-gen generate --from-directory <dir> -o apple-constraints.json
                The cupertino-symbolgraphs corpus is the canonical home for these *.symbols.json files.
                """
            }
        }
    }
}
