import Foundation
import MCPCore
import SampleIndexModels
import SearchModels
import SharedConstants

// MARK: - Typed MCP Output

extension CompositeToolProvider {
    enum ToolOutputFormat: String {
        case json
        case markdown
    }

    static func mcpToolOutputFormat(
        args: MCP.SharedTools.ArgumentExtractor
    ) throws -> ToolOutputFormat {
        let raw = args.optional(
            Shared.Constants.Search.schemaParamFormat,
            default: Shared.Constants.Search.formatValueMarkdown
        )
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case Shared.Constants.Search.formatValueJSON:
            return .json
        case Shared.Constants.Search.formatValueMarkdown, "md":
            return .markdown
        default:
            throw Shared.Core.ToolError.invalidArgument(
                Shared.Constants.Search.schemaParamFormat,
                "Invalid format `\(raw)`. Valid values: json, markdown."
            )
        }
    }

    static func textResult(_ text: String) -> MCP.Core.Protocols.CallToolResult {
        MCP.Core.Protocols.CallToolResult(content: [.text(MCP.Core.Protocols.TextContent(text: text))])
    }

    static func formatListSamplesJSON(
        projects: [Sample.Index.Project],
        totalProjects: Int,
        totalFiles: Int,
        framework: String?,
        limit: Int
    ) -> String {
        encodeToolJSON(ListSamplesJSON(
            totalProjects: totalProjects,
            totalFiles: totalFiles,
            framework: framework,
            limit: limit,
            projects: projects.map(SampleProjectJSON.init)
        ))
    }

    static func formatReadSampleJSON(
        project: Sample.Index.Project,
        files: [Sample.Index.File]
    ) -> String {
        encodeToolJSON(ReadSampleJSON(
            id: project.id,
            title: project.title,
            description: project.description,
            frameworks: project.frameworks,
            readme: project.readme,
            webURL: project.webURL,
            zipFilename: project.zipFilename,
            fileCount: project.fileCount,
            totalSize: project.totalSize,
            deploymentTargets: project.deploymentTargets,
            availabilitySource: project.availabilitySource,
            files: files.map(SampleFileSummaryJSON.init)
        ))
    }

    static func formatReadSampleFileJSON(
        file: Sample.Index.File,
        language: String
    ) -> String {
        encodeToolJSON(ReadSampleFileJSON(file: file, language: language))
    }

    static func formatSymbolSearchJSON(
        filters: SymbolFiltersJSON,
        results: [Search.SymbolSearchResult]
    ) -> String {
        encodeToolJSON(SymbolSearchJSON(
            filters: filters,
            results: results.map(SymbolResultJSON.init)
        ))
    }

    static func formatGenericsJSON(
        filters: SymbolFiltersJSON,
        appleDocs: [Search.SymbolSearchResult],
        samples: [Sample.Index.FileSearchResult],
        packages: [Search.Result]
    ) -> String {
        encodeToolJSON(GenericSearchJSON(
            filters: filters,
            appleDocs: appleDocs.map(SymbolResultJSON.init),
            samples: samples.map(SampleFileSearchResultJSON.init),
            packages: packages.map(SearchResultJSON.init)
        ))
    }

    static func formatInheritanceNotFoundJSON(
        symbol: String,
        message: String
    ) -> String {
        encodeToolJSON(InheritanceJSON(
            symbol: symbol,
            status: "not_found",
            message: message,
            candidates: [],
            ancestors: [],
            descendants: []
        ))
    }

    static func formatInheritanceAmbiguousJSON(
        symbol: String,
        message: String,
        candidates: [Search.InheritanceCandidate]
    ) -> String {
        encodeToolJSON(InheritanceJSON(
            symbol: symbol,
            status: "ambiguous",
            message: message,
            candidates: candidates.map(InheritanceCandidateJSON.init),
            ancestors: [],
            descendants: []
        ))
    }

    static func formatInheritanceJSON(
        candidate: Search.InheritanceCandidate,
        direction: Search.InheritanceDirection,
        depth: Int,
        tree: Search.InheritanceTree,
        searchIndex: any Search.Database
    ) async throws -> String {
        let status = tree.isEmpty ? "no_data" : "ok"
        let message = tree.isEmpty
            ? Search.emptyInheritanceMessage(kind: candidate.kind, direction: direction)
            : nil
        return try await encodeToolJSON(InheritanceJSON(
            symbol: candidate.title,
            status: status,
            framework: candidate.framework,
            uri: candidate.uri,
            kind: candidate.kind,
            direction: direction.rawValue,
            depth: depth,
            message: message,
            candidates: [InheritanceCandidateJSON(candidate)],
            ancestors: inheritanceNodesJSON(tree.ancestors, searchIndex: searchIndex),
            descendants: inheritanceNodesJSON(tree.descendants, searchIndex: searchIndex)
        ))
    }

    private static func inheritanceNodesJSON(
        _ nodes: [Search.InheritanceNode],
        searchIndex: any Search.Database
    ) async throws -> [InheritanceNodeJSON] {
        var output: [InheritanceNodeJSON] = []
        for node in nodes {
            let title = try await documentTitle(uri: node.uri, searchIndex: searchIndex)
                ?? fallbackTitle(uri: node.uri)
            try await output.append(InheritanceNodeJSON(
                uri: node.uri,
                title: title,
                children: inheritanceNodesJSON(node.children, searchIndex: searchIndex)
            ))
        }
        return output
    }

    private static func documentTitle(
        uri: String,
        searchIndex: any Search.Database
    ) async throws -> String? {
        guard let content = try await searchIndex.getDocumentContent(uri: uri, format: .json) else {
            return nil
        }
        let data = Data(content.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["title"] as? String,
              !title.isEmpty
        else {
            return nil
        }
        return title.replacingOccurrences(of: " | Apple Developer Documentation", with: "")
    }

    private static func fallbackTitle(uri: String) -> String {
        let withoutFragment = uri.split(separator: "#", maxSplits: 1).first.map(String.init) ?? uri
        let lastPath = withoutFragment.split(separator: "/").last.map(String.init) ?? uri
        return lastPath.removingPercentEncoding ?? lastPath
    }

    private static func encodeToolJSON(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{ \"error\": \"Failed to encode JSON: \(error.localizedDescription)\" }"
        }
    }
}

extension CompositeToolProvider {
    struct SymbolFiltersJSON: Encodable {
        let query: String?
        let kind: String?
        let isAsync: Bool?
        let wrapper: String?
        let pattern: String?
        let protocolName: String?
        let constraint: String?
        let framework: String?
        let limit: Int
        let minIOS: String?
        let minMacOS: String?
        let minTvOS: String?
        let minWatchOS: String?
        let minVisionOS: String?

        init(
            query: String? = nil,
            kind: String? = nil,
            isAsync: Bool? = nil,
            wrapper: String? = nil,
            pattern: String? = nil,
            protocolName: String? = nil,
            constraint: String? = nil,
            framework: String?,
            limit: Int,
            platform: PlatformArgs
        ) {
            self.query = query
            self.kind = kind
            self.isAsync = isAsync
            self.wrapper = wrapper
            self.pattern = pattern
            self.protocolName = protocolName
            self.constraint = constraint
            self.framework = framework
            self.limit = limit
            minIOS = platform.minIOS
            minMacOS = platform.minMacOS
            minTvOS = platform.minTvOS
            minWatchOS = platform.minWatchOS
            minVisionOS = platform.minVisionOS
        }

        enum CodingKeys: String, CodingKey {
            case query
            case kind
            case isAsync = "is_async"
            case wrapper
            case pattern
            case protocolName = "protocol"
            case constraint
            case framework
            case limit
            case minIOS = "min_ios"
            case minMacOS = "min_macos"
            case minTvOS = "min_tvos"
            case minWatchOS = "min_watchos"
            case minVisionOS = "min_visionos"
        }
    }

    private struct ListSamplesJSON: Encodable {
        let totalProjects: Int
        let totalFiles: Int
        let framework: String?
        let limit: Int
        let projects: [SampleProjectJSON]
    }

    private struct ReadSampleJSON: Encodable {
        let id: String
        let title: String
        let description: String
        let frameworks: [String]
        let readme: String?
        let webURL: String
        let zipFilename: String
        let fileCount: Int
        let totalSize: Int
        let deploymentTargets: [String: String]
        let availabilitySource: String?
        let files: [SampleFileSummaryJSON]
    }

    private struct ReadSampleFileJSON: Encodable {
        let projectId: String
        let path: String
        let filename: String
        let folder: String
        let fileExtension: String
        let language: String
        let size: Int
        let availableAttrsJSON: String?
        let content: String

        init(file: Sample.Index.File, language: String) {
            projectId = file.projectId
            path = file.path
            filename = file.filename
            folder = file.folder
            fileExtension = file.fileExtension
            self.language = language
            size = file.size
            availableAttrsJSON = file.availableAttrsJSON
            content = file.content
        }
    }

    private struct SampleProjectJSON: Encodable {
        let id: String
        let title: String
        let description: String
        let frameworks: [String]
        let readme: String?
        let webURL: String
        let zipFilename: String
        let fileCount: Int
        let totalSize: Int
        let deploymentTargets: [String: String]
        let availabilitySource: String?

        init(_ project: Sample.Index.Project) {
            id = project.id
            title = project.title
            description = project.description
            frameworks = project.frameworks
            readme = project.readme
            webURL = project.webURL
            zipFilename = project.zipFilename
            fileCount = project.fileCount
            totalSize = project.totalSize
            deploymentTargets = project.deploymentTargets
            availabilitySource = project.availabilitySource
        }
    }

    private struct SampleFileSummaryJSON: Encodable {
        let projectId: String
        let path: String
        let filename: String
        let folder: String
        let fileExtension: String
        let size: Int
        let availableAttrsJSON: String?

        init(_ file: Sample.Index.File) {
            projectId = file.projectId
            path = file.path
            filename = file.filename
            folder = file.folder
            fileExtension = file.fileExtension
            size = file.size
            availableAttrsJSON = file.availableAttrsJSON
        }
    }

    private struct SampleFileSearchResultJSON: Encodable {
        let projectId: String
        let path: String
        let filename: String
        let snippet: String
        let rank: Double
        let score: Double

        init(_ result: Sample.Index.FileSearchResult) {
            projectId = result.projectId
            path = result.path
            filename = result.filename
            snippet = result.snippet
            rank = result.rank
            score = -result.rank
        }
    }

    private struct SymbolSearchJSON: Encodable {
        let filters: SymbolFiltersJSON
        let results: [SymbolResultJSON]
    }

    private struct GenericSearchJSON: Encodable {
        let filters: SymbolFiltersJSON
        let appleDocs: [SymbolResultJSON]
        let samples: [SampleFileSearchResultJSON]
        let packages: [SearchResultJSON]

        enum CodingKeys: String, CodingKey {
            case filters
            case appleDocs = "apple_docs"
            case samples
            case packages
        }
    }

    private struct SymbolResultJSON: Encodable {
        let docUri: String
        let docTitle: String
        let framework: String
        let symbolName: String
        let symbolKind: String
        let signature: String?
        let attributes: String?
        let conformances: String?
        let genericParams: String?
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
            case genericParams = "generic_params"
            case isAsync = "is_async"
            case isPublic = "is_public"
        }

        init(_ result: Search.SymbolSearchResult) {
            docUri = result.docUri
            docTitle = result.docTitle
            framework = result.framework
            symbolName = result.symbolName
            symbolKind = result.symbolKind
            signature = result.signature
            attributes = result.attributes
            conformances = result.conformances
            genericParams = result.genericParams
            isAsync = result.isAsync
            isPublic = result.isPublic
        }
    }

    private struct SearchResultJSON: Encodable {
        let uri: String
        let source: String
        let framework: String
        let title: String
        let summary: String
        let filePath: String
        let wordCount: Int
        let rank: Double
        let score: Double

        enum CodingKeys: String, CodingKey {
            case uri
            case source
            case framework
            case title
            case summary
            case filePath = "file_path"
            case wordCount = "word_count"
            case rank
            case score
        }

        init(_ result: Search.Result) {
            uri = result.uri
            source = result.source
            framework = result.framework
            title = result.title
            summary = result.cleanedSummary
            filePath = result.filePath
            wordCount = result.wordCount
            rank = result.rank
            score = result.score
        }
    }

    private struct InheritanceJSON: Encodable {
        let symbol: String
        let status: String
        let framework: String?
        let uri: String?
        let kind: String?
        let direction: String?
        let depth: Int?
        let message: String?
        let candidates: [InheritanceCandidateJSON]
        let ancestors: [InheritanceNodeJSON]
        let descendants: [InheritanceNodeJSON]

        init(
            symbol: String,
            status: String,
            framework: String? = nil,
            uri: String? = nil,
            kind: String? = nil,
            direction: String? = nil,
            depth: Int? = nil,
            message: String? = nil,
            candidates: [InheritanceCandidateJSON],
            ancestors: [InheritanceNodeJSON],
            descendants: [InheritanceNodeJSON]
        ) {
            self.symbol = symbol
            self.status = status
            self.framework = framework
            self.uri = uri
            self.kind = kind
            self.direction = direction
            self.depth = depth
            self.message = message
            self.candidates = candidates
            self.ancestors = ancestors
            self.descendants = descendants
        }
    }

    private struct InheritanceCandidateJSON: Encodable {
        let uri: String
        let title: String
        let framework: String
        let kind: String?

        init(_ candidate: Search.InheritanceCandidate) {
            uri = candidate.uri
            title = candidate.title
            framework = candidate.framework
            kind = candidate.kind
        }
    }

    private struct InheritanceNodeJSON: Encodable {
        let uri: String
        let title: String
        let children: [InheritanceNodeJSON]
    }
}
