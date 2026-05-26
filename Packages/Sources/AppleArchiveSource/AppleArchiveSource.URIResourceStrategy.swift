import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - AppleArchiveURIResourceStrategy

/// `Search.URIResourceStrategy` concrete for the `apple-archive://`
/// scheme. Lifts the pre-2026-05-26 if/elseif arm in
/// `MCP.Support.DocsResourceProvider.{listResources,readResource}` and
/// the `listArchiveResources` helper into this target.
public struct AppleArchiveURIResourceStrategy: Search.URIResourceStrategy {
    public let scheme = Shared.Constants.Search.appleArchiveScheme

    public init() {}

    public func listResources(env: Search.URIResourceEnvironment) async throws -> [Search.URIResource] {
        // #1046: resolve symlinks before listing.
        let root = env.sourceDirectory.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }

        let guides = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )

        var resources: [Search.URIResource] = []
        for guide in guides where guide.hasDirectoryPath {
            let guideUID = guide.lastPathComponent
            let files = try FileManager.default.contentsOfDirectory(
                at: guide,
                includingPropertiesForKeys: nil
            )

            for file in files where file.pathExtension == "md" {
                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "\(scheme)\(guideUID)/\(filename)"
                resources.append(Search.URIResource(
                    uri: uri,
                    name: filename.replacingOccurrences(of: "-", with: " ").capitalized,
                    description: "Apple Archive documentation"
                ))
            }
        }
        return resources
    }

    public func readMarkdown(
        uri: String,
        env: Search.URIResourceEnvironment
    ) async throws -> String? {
        // Expected URI shape: apple-archive://guideUID/filename
        guard let components = parse(uri: uri) else { return nil }

        let filePath = env.sourceDirectory
            .appendingPathComponent(components.guideUID)
            .appendingPathComponent("\(components.filename).md")

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }
        return try String(contentsOf: filePath, encoding: .utf8)
    }

    private func parse(uri: String) -> (guideUID: String, filename: String)? {
        guard uri.hasPrefix(scheme) else { return nil }
        let path = uri.replacingOccurrences(of: scheme, with: "")
        let components = path.split(separator: "/", maxSplits: 1)
        guard components.count == 2 else { return nil }
        return (guideUID: String(components[0]), filename: String(components[1]))
    }
}
