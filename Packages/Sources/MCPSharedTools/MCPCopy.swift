import Foundation

// MARK: - MCPCopy

/// MCP-protocol output strings extracted from `Shared.Constants.Search`.
///
/// These are the values that `MCPSupport` and `SearchToolProvider` serialize
/// back to MCP clients: tool descriptions, resource template URIs, resource
/// descriptions, and MIME types. Anything that a non-MCP package would also
/// need (URI schemes, tool/command names, JSON schema parameter names,
/// format values, Swift Evolution prefixes, tips, messages) stays in
/// `Shared.Constants.Search` so the formatters and CLI keep working without
/// an MCP-adjacent dependency.
public enum MCPCopy {
    // MARK: Resource Template URIs

    /// Apple documentation resource template
    public static let templateAppleDocs = "apple-docs://{framework}/{page}"

    /// Swift Evolution resource template
    public static let templateSwiftEvolution = "swift-evolution://{proposalID}"

    // MARK: Resource Descriptions

    /// Apple documentation resource description prefix
    public static let appleDocsDescriptionPrefix = "Apple Documentation:"

    /// Swift Evolution proposal resource description
    public static let swiftEvolutionDescription = "Swift Evolution Proposal"

    /// Apple documentation template name
    public static let appleDocsTemplateName = "Apple Documentation Page"

    /// Apple documentation template description
    public static let appleDocsTemplateDescription = "Access Apple documentation by framework and page name"

    /// Swift Evolution template description
    public static let swiftEvolutionTemplateDescription =
        "Access Swift Evolution proposals by ID (e.g., SE-0001 or ST-0001)"

    // MARK: MIME Types

    /// Markdown MIME type
    public static let mimeTypeMarkdown = "text/markdown"

    // MARK: Tool Descriptions

    /// Unified search tool description
    public static let toolSearchDescription = """
    Search Apple documentation and Swift Evolution proposals by keywords. \
    Returns a ranked list of relevant documents with URIs that can be read using resources/read.

    **By default, searches ALL sources** (docs, samples, HIG, etc.) for comprehensive results. \
    Use `source` parameter to narrow to a specific source.

    **Semantic search:** Includes AST-extracted symbols from Swift source code. \
    Find @Observable classes, async functions, View conformances, protocol conformances, etc. \
    Works across both documentation and sample code.

    **Source options** (use `source` parameter to narrow scope):
    - (default): Search ALL sources at once
    - apple-docs: Modern Apple API documentation only
    - samples: Sample code projects with working examples
    - hig: Human Interface Guidelines
    - apple-archive: Legacy guides (Core Animation, Quartz 2D, KVO/KVC)
    - swift-evolution: Swift Evolution proposals
    - swift-org: Swift.org documentation
    - swift-book: The Swift Programming Language book
    - packages: Swift package documentation

    **IMPORTANT:** For foundational topics (Core Animation, Quartz 2D, KVO/KVC, threading), \
    use source=apple-archive. For working code examples, use source=samples.

    **Optional parameters:**
    - source: Filter by documentation source (see above)
    - framework: Filter by framework (e.g. swiftui, foundation)
    - include_archive: Include archive results when source is not specified
    - min_ios/min_macos/min_tvos/min_watchos/min_visionos: Filter by API availability
    - limit: Maximum results (default 20)
    """

    /// List frameworks tool description
    public static let toolListFrameworksDescription = """
    List all available frameworks in the documentation index with document counts. \
    Useful for discovering what documentation is available.
    """

    /// Read document tool description
    public static let toolReadDocumentDescription = """
    Read a document by URI. Returns the full document content in the requested format. \
    Use URIs from search_docs results. Format parameter: 'json' (default, structured) or 'markdown' (rendered).
    """

    // MARK: Sample Code Tool Descriptions

    /// List samples tool description
    public static let toolListSamplesDescription = """
    List all indexed Apple sample code projects with metadata. \
    Useful for discovering available sample code before searching.
    """

    /// Read sample tool description
    public static let toolReadSampleDescription = """
    Read a sample code project's README and metadata by project ID. \
    Use project IDs from search_samples or list_samples results.
    """

    /// Read sample file tool description
    public static let toolReadSampleFileDescription = """
    Read a specific source file from a sample code project. \
    Requires project_id and file_path parameters. File paths are relative to project root.
    """

    // MARK: Semantic Search Tool Descriptions (#81)

    /// Search symbols tool description
    public static let toolSearchSymbolsDescription = """
    Search Swift symbols by type and name pattern. Uses SwiftSyntax AST extraction. \
    Find structs, classes, actors, protocols, functions, properties by kind and name.

    **Symbol kinds:** struct, class, actor, enum, protocol, extension, function, property, typealias

    **Parameters:**
    - query: Symbol name pattern (partial match supported)
    - kind: Filter by symbol kind (optional)
    - is_async: Filter async functions only (optional)
    - framework: Filter by framework (optional)
    - limit: Maximum results (default 20)

    **Examples:**
    - Find all actors: kind=actor
    - Find async functions: is_async=true
    - Find View structs: query=View, kind=struct
    """

    /// Search property wrappers tool description
    public static let toolSearchPropertyWrappersDescription = """
    Find Swift property wrapper usage patterns across documentation and samples. \
    Essential for discovering SwiftUI state management patterns.

    **Common wrappers:** @State, @Binding, @StateObject, @ObservedObject, @Observable, \
    @Environment, @EnvironmentObject, @Published, @AppStorage, @MainActor, @Sendable

    **Parameters:**
    - wrapper: Property wrapper name (with or without @)
    - framework: Filter by framework (optional)
    - limit: Maximum results (default 20)

    **Examples:**
    - Find @Observable usage: wrapper=Observable
    - Find @MainActor usage: wrapper=MainActor
    """

    /// Search concurrency patterns tool description
    public static let toolSearchConcurrencyDescription = """
    Find Swift concurrency patterns: async/await, actors, Sendable conformances. \
    Discover real-world concurrency usage in Apple documentation and samples.

    **Pattern options:** async, actor, sendable, mainactor, task, asyncsequence

    **Parameters:**
    - pattern: Concurrency pattern to search for
    - framework: Filter by framework (optional)
    - limit: Maximum results (default 20)

    **Examples:**
    - Find async functions: pattern=async
    - Find actor declarations: pattern=actor
    - Find Sendable types: pattern=sendable
    """

    /// Search conformances tool description
    public static let toolSearchConformancesDescription = """
    Find types by protocol conformance. Discover how protocols are implemented \
    across Apple documentation and sample code.

    **Common protocols:** View, Codable, Hashable, Equatable, Identifiable, \
    ObservableObject, Sendable, AsyncSequence, Error

    **Parameters:**
    - protocol: Protocol name to search for
    - framework: Filter by framework (optional)
    - limit: Maximum results (default 20)

    **Examples:**
    - Find View conformances: protocol=View
    - Find Sendable types: protocol=Sendable
    """
}
