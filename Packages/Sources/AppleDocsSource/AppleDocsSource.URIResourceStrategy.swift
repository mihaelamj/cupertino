import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - AppleDocsURIResourceStrategy

/// `Search.URIResourceStrategy` concrete for the `apple-docs://` scheme.
/// Lifts the pre-2026-05-26 if/elseif arm in
/// `MCP.Support.DocsResourceProvider.{listResources,readResource}` plus
/// the bespoke `parseAppleDocsURI`, `isFrameworkRootPage`, and
/// `extractTitle` helpers into this target.
///
/// The strategy handles the `.json` (lossless `StructuredDocumentationPage`)
/// vs `.md` filesystem fallback for both modern + legacy
/// (`documentation_<framework>` pre-#587) on-disk shapes.
public struct AppleDocsURIResourceStrategy: Search.URIResourceStrategy {
    public let scheme = Shared.Constants.Search.appleDocsScheme

    public init() {}

    public func listResources(env: Search.URIResourceEnvironment) async throws -> [Search.URIResource] {
        // The apple-docs listResources slice is metadata-driven (the
        // pre-fix call in MCP read CrawlMetadata.pages, applied the
        // framework-root filter, and emitted one entry per matched
        // page). If the composition root didn't load metadata for this
        // call (e.g. the file is absent), the slice is empty —
        // matching the pre-fix "loud-fail surface" log + skip
        // semantics, but the loud log lives in the MCP layer where the
        // logger has the right category.
        guard let metadata = env.metadata else { return [] }

        var resources: [Search.URIResource] = []
        for (urlString, pageMetadata) in metadata.pages {
            guard let parsedURL = URL(string: urlString) else {
                env.logger.warning(
                    "AppleDocsURIResourceStrategy: skipping malformed URL key in "
                        + "CrawlMetadata.pages: '\(urlString)' "
                        + "(framework: \(pageMetadata.framework))",
                    category: .mcp
                )
                continue
            }
            guard Self.isFrameworkRootPage(url: parsedURL, framework: pageMetadata.framework) else {
                continue
            }
            // #587 / BUG 1 fix preserved: use the lossless
            // `appleDocsURI(from:)` helper so the resources/list URI
            // matches the indexer-stored URI in `docs_metadata`.
            let uri = Shared.Models.URLUtilities.appleDocsURI(from: parsedURL)
                ?? "\(scheme)\(pageMetadata.framework)/\(Shared.Models.URLUtilities.filename(from: parsedURL))"
            resources.append(Search.URIResource(
                uri: uri,
                name: Self.extractTitle(from: urlString),
                description: "Apple Documentation: \(pageMetadata.framework)"
            ))
        }
        return resources
    }

    public func readMarkdown(
        uri: String,
        env: Search.URIResourceEnvironment
    ) async throws -> String? {
        // Two URI shapes (#588 — `appleDocsURI(from:)` emits both):
        //   * `apple-docs://<framework>/<rest-of-path>` — sub-page URI.
        //   * `apple-docs://<framework>` — framework-root URI.
        guard let components = Self.parse(uri: uri) else { return nil }

        let baseDir = env.sourceDirectory.appendingPathComponent(components.framework)
        let isFrameworkRoot = components.filename == components.framework

        // Probe sequence: try `<filename>.json`, then `.md`. For the
        // framework-root URI shape, older crawls wrote the page under
        // the legacy `documentation_<framework>` basename (filename(from:)
        // output pre-#587), so also try that shape as a defence against
        // stale on-disk files.
        var probes: [URL] = [
            baseDir.appendingPathComponent("\(components.filename).json"),
            baseDir.appendingPathComponent("\(components.filename)\(Shared.Constants.FileName.markdownExtension)"),
        ]
        if isFrameworkRoot {
            let legacyBase = "documentation_\(components.framework)"
            probes.append(baseDir.appendingPathComponent("\(legacyBase).json"))
            probes.append(baseDir.appendingPathComponent("\(legacyBase)\(Shared.Constants.FileName.markdownExtension)"))
        }

        for path in probes where FileManager.default.fileExists(atPath: path.path) {
            if path.pathExtension == "json" {
                let jsonData = try Data(contentsOf: path)
                let page = try Shared.Utils.JSONCoding.decode(
                    Shared.Models.StructuredDocumentationPage.self,
                    from: jsonData
                )
                guard let rawMarkdown = page.rawMarkdown else { return nil }
                return rawMarkdown
            }
            return try String(contentsOf: path, encoding: .utf8)
        }
        return nil
    }

    // MARK: - Lifted helpers

    public static func parse(uri: String) -> (framework: String, filename: String)? {
        guard uri.hasPrefix(Shared.Constants.Search.appleDocsScheme) else { return nil }
        let path = uri.replacingOccurrences(of: Shared.Constants.Search.appleDocsScheme, with: "")
        let components = path.split(separator: "/", maxSplits: 1)

        switch components.count {
        case 1:
            let framework = String(components[0])
            guard !framework.isEmpty else { return nil }
            return (framework: framework, filename: framework)
        case 2:
            return (framework: String(components[0]), filename: String(components[1]))
        default:
            return nil
        }
    }

    /// Returns `true` when `url` points at a framework root page — the
    /// only apple-docs entries that belong in `resources/list`.
    public static func isFrameworkRootPage(url: URL, framework: String) -> Bool {
        let normalizedPath = url.path.hasSuffix("/")
            ? String(url.path.dropLast())
            : url.path
        let expected = "/documentation/\(framework.lowercased())"
        return normalizedPath.lowercased() == expected
    }

    public static func extractTitle(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        let lastComponent = url.lastPathComponent
        return lastComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
