import ArgumentParser
import Foundation
import Logging
import LoggingModels
import Search
import SearchModels
import SharedConstants

// MARK: - Inheritance Command (#274)

/// CLI command for walking class-inheritance chains stored in the
/// `inheritance` edge table introduced in v15 schema. Mirrors the
/// `get_inheritance` MCP tool surface — same parameters, same
/// disambiguation behaviour. Useful for UIKit / AppKit / Foundation
/// class hierarchies (`UIButton ← UIControl ← UIView ← UIResponder
/// ← NSObject`); non-class kinds (struct, enum, protocol) return
/// "no inheritance data" honestly.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension CLIImpl.Command {
    struct Inheritance: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "inheritance",
            abstract: "Walk class inheritance chains (Apple class-based APIs)",
            discussion: """
            Walks the `inheritance` edge table populated at index time from
            Apple's DocC `relationshipsSections`. Useful for UIKit / AppKit /
            Foundation class hierarchies.

            EXAMPLES:
              cupertino inheritance UIButton                      # walk up by default
              cupertino inheritance UIControl --direction down    # walk down
              cupertino inheritance UIView --direction both --depth 1
              cupertino inheritance Color                         # ambiguous → disambiguation list

            DIRECTIONS:
              up    Ancestors only (UIButton → UIControl → UIView → ...)
              down  Descendants only (UIControl → UIButton / UISwitch / ...)
              both  Both directions from the start node

            NON-CLASS KINDS:
              SwiftUI structs / enums / protocols have no inheritance edges
              and return "no inheritance data". This is correct behaviour —
              value types don't inherit in Swift.
            """
        )

        @Argument(help: "Symbol name to walk from (e.g. UIButton, NSView)")
        var symbol: String

        @Option(
            name: .long,
            help: "Direction: up (ancestors), down (descendants), both"
        )
        var direction: WalkDirection = .up

        @Option(
            name: .long,
            help: "Maximum walk depth (default 5)"
        )
        var depth: Int = 5

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

        @Option(
            name: .long,
            help: "Disambiguate to a specific framework when the symbol exists in multiple"
        )
        var framework: String?

        // swiftlint:disable:next function_body_length
        mutating func run() async throws {
            guard depth > 0 else {
                Cupertino.Context.composition.logging.recording.error(
                    "❌ --depth must be at least 1"
                )
                throw ExitCode.failure
            }

            let searchDBURL = searchDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Paths.live().searchDatabase

            guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
                Cupertino.Context.composition.logging.recording.error(
                    "❌ search.db not found at \(searchDBURL.path). Run `cupertino setup` first."
                )
                throw ExitCode.failure
            }

            let index = try await SearchModule.Index(
                dbPath: searchDBURL,
                logger: Cupertino.Context.composition.logging.recording
            )
            defer { Task { await index.disconnect() } }

            // Resolve symbol → URI. Ambiguity disambiguation pattern: if
            // multiple frameworks define the same title (Color in SwiftUI
            // vs AppKit), require the user to pick one via --framework
            // unless they already passed it.
            let candidates = try await index.resolveSymbolURIs(title: symbol)
            let candidate: SearchModule.InheritanceCandidate
            switch candidates.count {
            case 0:
                emitNotFound(symbol: symbol)
                return
            case 1:
                candidate = candidates[0]
            default:
                if let framework {
                    guard let match = candidates.first(where: { $0.framework.lowercased() == framework.lowercased() }) else {
                        Cupertino.Context.composition.logging.recording.error(
                            "❌ Symbol `\(symbol)` not found in framework `\(framework)`. " +
                                "Try `cupertino list-frameworks` to see valid values."
                        )
                        throw ExitCode.failure
                    }
                    candidate = match
                } else {
                    emitDisambiguation(symbol: symbol, candidates: candidates)
                    throw ExitCode.failure
                }
            }

            let tree = try await index.walkInheritance(
                startURI: candidate.uri,
                direction: direction.searchDirection,
                maxDepth: depth
            )

            switch format {
            case .text:
                emitText(symbol: candidate.title, candidate: candidate, tree: tree)
            case .json:
                try emitJSON(symbol: candidate.title, candidate: candidate, tree: tree)
            case .markdown:
                emitMarkdown(symbol: candidate.title, candidate: candidate, tree: tree)
            }
        }

        // MARK: - Output

        private func emitNotFound(symbol: String) {
            Cupertino.Context.composition.logging.recording.output(
                "No symbol named `\(symbol)` in apple-docs. Did you mean to run `cupertino search \(symbol)` first?"
            )
        }

        private func emitDisambiguation(symbol: String, candidates: [SearchModule.InheritanceCandidate]) {
            var out = "`\(symbol)` is ambiguous across \(candidates.count) frameworks:\n\n"
            for candidate in candidates {
                out += "  - \(candidate.title) in \(candidate.framework) (\(candidate.uri))\n"
            }
            out += "\nRe-run with `--framework <name>` to pick one."
            Cupertino.Context.composition.logging.recording.error(out)
        }

        private func emitText(symbol: String, candidate: SearchModule.InheritanceCandidate, tree: SearchModule.InheritanceTree) {
            var out = "\(symbol) (\(candidate.uri))\n"
            if tree.isEmpty {
                out += "  no inheritance data — Swift value types and protocols don't carry inherits-from edges.\n"
            }
            if !tree.ancestors.isEmpty {
                out += "  inherits from:\n"
                renderText(tree.ancestors, indent: 4, into: &out)
            }
            if !tree.descendants.isEmpty {
                out += "  inherited by:\n"
                renderText(tree.descendants, indent: 4, into: &out)
            }
            Cupertino.Context.composition.logging.recording.output(out)
        }

        private func renderText(_ nodes: [SearchModule.InheritanceNode], indent: Int, into out: inout String) {
            let pad = String(repeating: " ", count: indent)
            for node in nodes {
                out += "\(pad)\(node.uri)\n"
                if !node.children.isEmpty {
                    renderText(node.children, indent: indent + 2, into: &out)
                }
            }
        }

        private func emitMarkdown(symbol: String, candidate: SearchModule.InheritanceCandidate, tree: SearchModule.InheritanceTree) {
            var out = "# Inheritance: \(symbol)\n\n"
            out += "**URI:** `\(candidate.uri)`  **Framework:** `\(candidate.framework)`\n\n"
            if tree.isEmpty {
                out += "_No inheritance data — Swift value types and protocols don't carry inherits-from edges._\n"
            }
            if !tree.ancestors.isEmpty {
                out += "## Inherits from\n\n"
                renderMarkdown(tree.ancestors, indent: 0, into: &out)
                out += "\n"
            }
            if !tree.descendants.isEmpty {
                out += "## Inherited by\n\n"
                renderMarkdown(tree.descendants, indent: 0, into: &out)
            }
            Cupertino.Context.composition.logging.recording.output(out)
        }

        private func renderMarkdown(_ nodes: [SearchModule.InheritanceNode], indent: Int, into out: inout String) {
            let pad = String(repeating: "  ", count: indent)
            for node in nodes {
                out += "\(pad)- `\(node.uri)`\n"
                if !node.children.isEmpty {
                    renderMarkdown(node.children, indent: indent + 1, into: &out)
                }
            }
        }

        private func emitJSON(symbol: String, candidate: SearchModule.InheritanceCandidate, tree: SearchModule.InheritanceTree) throws {
            let payload = JSONPayload(
                symbol: symbol,
                framework: candidate.framework,
                uri: candidate.uri,
                ancestors: tree.ancestors.map(JSONNode.init),
                descendants: tree.descendants.map(JSONNode.init)
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

// MARK: - Option types

extension CLIImpl.Command.Inheritance {
    enum WalkDirection: String, ExpressibleByArgument, CaseIterable {
        case up
        case down
        case both

        var searchDirection: SearchModule.InheritanceDirection {
            switch self {
            case .up: return .up
            case .down: return .down
            case .both: return .both
            }
        }
    }

    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case text
        case json
        case markdown
    }

    /// JSON output shape — a flat top-level plus two nested trees.
    private struct JSONPayload: Codable {
        let symbol: String
        let framework: String
        let uri: String
        let ancestors: [JSONNode]
        let descendants: [JSONNode]
    }

    private struct JSONNode: Codable {
        let uri: String
        let children: [JSONNode]

        init(_ node: SearchModule.InheritanceNode) {
            uri = node.uri
            children = node.children.map(JSONNode.init)
        }
    }
}
