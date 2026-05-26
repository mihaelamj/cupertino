import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - SwiftEvolutionURIResourceStrategy

/// `Search.URIResourceStrategy` concrete for the `swift-evolution://`
/// scheme. Lifts the pre-2026-05-26 if/elseif arm in
/// `MCP.Support.DocsResourceProvider.{listResources,readResource}` into
/// this target so adding a new MCP-resource source doesn't require
/// editing the central dispatcher.
public struct SwiftEvolutionURIResourceStrategy: Search.URIResourceStrategy {
    public let scheme = Shared.Constants.Search.swiftEvolutionScheme

    public init() {}

    public func listResources(env: Search.URIResourceEnvironment) async throws -> [Search.URIResource] {
        // #1046: resolve symlinks before listing — common dev setup
        // symlinks corpus dirs under ~/.cupertino-dev/.
        let root = env.sourceDirectory.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )

        return files
            .filter { $0.pathExtension == "md" }
            .filter {
                $0.lastPathComponent.hasPrefix(Shared.Constants.Search.sePrefix)
                    || $0.lastPathComponent.hasPrefix(Shared.Constants.Search.stPrefix)
            }
            .map { file in
                let proposalID = file.deletingPathExtension().lastPathComponent
                return Search.URIResource(
                    uri: "\(scheme)\(proposalID)",
                    name: proposalID,
                    description: "Swift Evolution proposal"
                )
            }
    }

    public func readMarkdown(
        uri: String,
        env: Search.URIResourceEnvironment
    ) async throws -> String? {
        // Expected URI shape: swift-evolution://SE-NNNN  (or ST-NNNN)
        guard let proposalID = parseProposalID(from: uri) else { return nil }

        // #1046: resolve symlinks before enumerating.
        let files = try FileManager.default.contentsOfDirectory(
            at: env.sourceDirectory.resolvingSymlinksInPath(),
            includingPropertiesForKeys: nil
        )

        guard let file = files.first(where: { $0.lastPathComponent.hasPrefix(proposalID) }) else {
            return nil
        }

        return try String(contentsOf: file, encoding: .utf8)
    }

    private func parseProposalID(from uri: String) -> String? {
        guard uri.hasPrefix(scheme) else { return nil }
        let proposalID = uri.replacingOccurrences(of: scheme, with: "")
        return proposalID.isEmpty ? nil : proposalID
    }
}
