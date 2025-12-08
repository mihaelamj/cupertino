# Search & Tool Provider Refactoring Analysis

**Date:** 2025-12-08
**Purpose:** Deep analysis of code duplication between CLI commands, MCP tools, and resource providers. Design protocol-based refactoring for perfect separation of concerns.

---

## Executive Summary

The codebase has **three parallel implementations** of similar functionality:
1. **CLI Commands** - `SearchCommand`, `ReadCommand`, `ListFrameworksCommand`, etc.
2. **MCP Tool Providers** - `DocumentationToolProvider`, `SampleCodeToolProvider`
3. **MCP Resource Providers** - `DocsResourceProvider`

All three share the same underlying data sources (`Search.Index`, `SampleIndex.Database`) but duplicate:
- Parameter extraction/validation
- Result formatting
- Error handling
- Database/file path resolution

**Goal:** Extract shared logic into source-specific **Service** and **Formatter** protocols.

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Interface Layer                         │
├─────────────────────────────────┬───────────────────────────────────┤
│         CLI Commands            │         MCP Tools/Resources       │
│  ┌───────────────────────────┐  │  ┌───────────────────────────┐   │
│  │ SearchCommand             │  │  │ DocumentationToolProvider │   │
│  │ ReadCommand               │  │  │ SampleCodeToolProvider    │   │
│  │ ListFrameworksCommand     │  │  │ DocsResourceProvider      │   │
│  │ SearchSamplesCommand      │  │  │ CompositeToolProvider     │   │
│  │ ListSamplesCommand        │  │  └───────────────────────────┘   │
│  │ ReadSampleCommand         │  │                                   │
│  │ ReadSampleFileCommand     │  │                                   │
│  └───────────────────────────┘  │                                   │
├─────────────────────────────────┴───────────────────────────────────┤
│                         Data Access Layer                            │
│  ┌───────────────────────────┐  ┌───────────────────────────┐      │
│  │ Search.Index              │  │ SampleIndex.Database      │      │
│  │ (SQLite FTS5)             │  │ (SQLite FTS5)             │      │
│  └───────────────────────────┘  └───────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

**Problem:** No shared service layer between CLI and MCP.

---

## Detailed Duplication Analysis

### 1. Error Types (4 duplicates!)

```swift
// DocumentationToolProvider.swift:288-302
enum DocumentationToolError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String)
}

// SampleCodeToolProvider.swift:311-325
enum SampleToolError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String)
}

// CompositeToolProvider.swift:63-77
enum UnifiedToolError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String)
}

// DocsResourceProvider.swift:333-349
enum ResourceError: Error, LocalizedError {
    case invalidURI(String)
    case notFound(String)
    case noDocumentation
}
```

**Verdict:** Extract to single `ToolError` enum in Shared.

---

### 2. Argument Extraction Pattern (repeated 15+ times)

```swift
// Pattern repeated in every tool handler:
guard let query = arguments?[Shared.Constants.MCP.schemaParamQuery]?.value as? String else {
    throw SampleToolError.missingArgument(Shared.Constants.MCP.schemaParamQuery)
}

let framework = arguments?[Shared.Constants.MCP.schemaParamFramework]?.value as? String
let defaultLimit = Shared.Constants.Limit.defaultSearchLimit
let requestedLimit = (arguments?[Shared.Constants.MCP.schemaParamLimit]?.value as? Int) ?? defaultLimit
let limit = min(requestedLimit, Shared.Constants.Limit.maxSearchLimit)
```

**Verdict:** Create `ArgumentExtractor` helper.

---

### 3. Markdown Formatting (5+ similar implementations)

| Location | Function | Lines |
|----------|----------|-------|
| `DocumentationToolProvider` | `handleSearchDocs` | 104-142 |
| `DocumentationToolProvider` | `handleSearchHIG` | 239-276 |
| `DocumentationToolProvider` | `handleListFrameworks` | 155-173 |
| `SampleCodeToolProvider` | `handleSearchSamples` | 101-156 |
| `SampleCodeToolProvider` | `handleListSamples` | 169-191 |
| `SampleCodeToolProvider` | `handleReadSample` | 209-247 |
| `SearchCommand` | `outputMarkdown` | 157-178 |
| `ListFrameworksCommand` | `outputMarkdown` | 124-141 |

**All use the same markdown patterns:**
```swift
"# Title\n\n"
"Found **\(count)** result(s):\n\n"
"## \(index + 1). \(title)\n\n"
"- **Field:** `\(value)`\n"
"---\n\n"
```

**Verdict:** Create source-specific `ResultFormatter` protocols.

---

### 4. CLI/MCP Functionality Mapping

| Functionality | CLI Command | MCP Tool | MCP Resource |
|--------------|-------------|----------|--------------|
| **Documentation** |
| Search docs | `SearchCommand` | `search_docs` | - |
| Search HIG | **MISSING** | `search_hig` | - |
| Read document | `ReadCommand` | `read_document` | `readResource` |
| List frameworks | `ListFrameworksCommand` | `list_frameworks` | - |
| **Sample Code** |
| Search samples | `SearchSamplesCommand` | `search_samples` | - |
| List samples | `ListSamplesCommand` | `list_samples` | - |
| Read sample | `ReadSampleCommand` | `read_sample` | - |
| Read sample file | `ReadSampleFileCommand` | `read_sample_file` | - |

**Missing CLI commands:**
- `cupertino search-hig` (or `search --source hig`)

---

### 5. Path Resolution (6 duplicates)

```swift
// Duplicated in SearchCommand, ReadCommand, ListFrameworksCommand,
// SearchSamplesCommand, ListSamplesCommand, ReadSampleCommand, ReadSampleFileCommand

private func resolveSearchDbPath() -> URL {
    if let searchDb {
        return URL(fileURLWithPath: searchDb).expandingTildeInPath
    }
    return Shared.Constants.defaultSearchDatabase
}

private extension URL {
    var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            let expandedPath = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath)
        }
        return self
    }
}
```

---

### 6. Database Lifecycle (7 duplicates)

```swift
// Every CLI command has this pattern:
let searchIndex = try await Search.Index(dbPath: dbPath)
defer {
    Task {
        await searchIndex.disconnect()
    }
}
```

---

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Interface Layer                              │
├─────────────────────────────────┬───────────────────────────────────┤
│         CLI Commands            │         MCP Providers              │
│  (thin wrappers using services) │  (thin wrappers using services)   │
├─────────────────────────────────┴───────────────────────────────────┤
│                         Service Layer (NEW)                          │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ protocol SearchService                                         │  │
│  │   func search(request:) -> [SearchResult]                      │  │
│  │   func read(uri:format:) -> String?                            │  │
│  │   func listFrameworks() -> [String: Int]                       │  │
│  ├───────────────────────────────────────────────────────────────┤  │
│  │ DocsSearchService: SearchService                               │  │
│  │ HIGSearchService: SearchService                                │  │
│  │ SampleSearchService: SearchService                             │  │
│  └───────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│                         Formatter Layer (NEW)                        │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ protocol ResultFormatter                                       │  │
│  │   func format(results:query:filters:) -> String                │  │
│  ├───────────────────────────────────────────────────────────────┤  │
│  │ TextFormatter, JSONFormatter, MarkdownFormatter                │  │
│  │ (per-source customization via configuration)                   │  │
│  └───────────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────┤
│                         Data Access Layer                            │
│  ┌───────────────────────────┐  ┌───────────────────────────────┐  │
│  │ Search.Index              │  │ SampleIndex.Database          │  │
│  └───────────────────────────┘  └───────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Protocol Definitions

### 1. SearchService Protocol

```swift
// Sources/Services/SearchService.swift

/// Protocol for all search operations across different sources
public protocol SearchService: Actor {
    associatedtype Query
    associatedtype Result

    /// Execute a search query
    func search(_ query: Query) async throws -> [Result]

    /// Get document by URI
    func read(uri: String, format: DocumentFormat) async throws -> String?
}

/// Common search request with source-specific extensions
public struct SearchQuery {
    public let text: String
    public let source: String?
    public let framework: String?
    public let language: String?
    public let limit: Int
    public let includeArchive: Bool

    public init(
        text: String,
        source: String? = nil,
        framework: String? = nil,
        language: String? = nil,
        limit: Int = Constants.Limit.defaultSearchLimit,
        includeArchive: Bool = false
    ) {
        self.text = text
        self.source = source
        self.framework = framework
        self.language = language
        self.limit = min(limit, Constants.Limit.maxSearchLimit)
        self.includeArchive = includeArchive
    }
}
```

### 2. Source-Specific Services

```swift
// Sources/Services/DocsSearchService.swift

public actor DocsSearchService: SearchService {
    private let index: Search.Index

    public init(index: Search.Index) {
        self.index = index
    }

    public func search(_ query: SearchQuery) async throws -> [Search.Result] {
        try await index.search(
            query: query.text,
            source: query.source,
            framework: query.framework,
            language: query.language,
            limit: query.limit,
            includeArchive: query.includeArchive
        )
    }

    public func read(uri: String, format: DocumentFormat) async throws -> String? {
        try await index.getDocumentContent(uri: uri, format: format)
    }

    public func listFrameworks() async throws -> [String: Int] {
        try await index.listFrameworks()
    }

    public func documentCount() async throws -> Int {
        try await index.documentCount()
    }
}

// Sources/Services/HIGSearchService.swift

public actor HIGSearchService: SearchService {
    private let docsService: DocsSearchService

    public struct HIGQuery {
        public let text: String
        public let platform: String?  // iOS, macOS, etc.
        public let category: String?  // foundations, patterns, etc.
        public let limit: Int
    }

    public init(index: Search.Index) {
        self.docsService = DocsSearchService(index: index)
    }

    public func search(_ query: HIGQuery) async throws -> [Search.Result] {
        var effectiveText = query.text
        if let platform = query.platform {
            effectiveText += " \(platform)"
        }
        if let category = query.category {
            effectiveText += " \(category)"
        }

        let searchQuery = SearchQuery(
            text: effectiveText,
            source: Constants.SourcePrefix.hig,
            limit: query.limit
        )

        return try await docsService.search(searchQuery)
    }

    public func read(uri: String, format: DocumentFormat) async throws -> String? {
        try await docsService.read(uri: uri, format: format)
    }
}

// Sources/Services/SampleSearchService.swift

public actor SampleSearchService: SearchService {
    private let database: SampleIndex.Database

    public struct SampleQuery {
        public let text: String
        public let framework: String?
        public let searchFiles: Bool
        public let limit: Int
    }

    public init(database: SampleIndex.Database) {
        self.database = database
    }

    public func search(_ query: SampleQuery) async throws -> SampleSearchResult {
        let projects = try await database.searchProjects(
            query: query.text,
            framework: query.framework,
            limit: query.limit
        )

        var files: [SampleIndex.Database.FileSearchResult] = []
        if query.searchFiles {
            files = try await database.searchFiles(
                query: query.text,
                projectId: nil,
                limit: query.limit
            )
        }

        return SampleSearchResult(projects: projects, files: files)
    }

    public func readProject(id: String) async throws -> SampleIndex.Database.Project? {
        try await database.getProject(id: id)
    }

    public func readFile(projectId: String, path: String) async throws -> SampleIndex.Database.File? {
        try await database.getFile(projectId: projectId, path: path)
    }

    public func listProjects(framework: String?, limit: Int) async throws -> [SampleIndex.Database.Project] {
        try await database.listProjects(framework: framework, limit: limit)
    }
}
```

### 3. ResultFormatter Protocol

```swift
// Sources/Services/Formatters/ResultFormatter.swift

/// Protocol for formatting search results to different output formats
public protocol ResultFormatter {
    associatedtype Input
    func format(_ input: Input) -> String
}

/// Configuration for search result formatting
public struct SearchResultFormatConfig {
    public let showScore: Bool
    public let showWordCount: Bool
    public let showSource: Bool
    public let showSeparators: Bool
    public let emptyMessage: String

    public static let cliDefault = SearchResultFormatConfig(
        showScore: false,
        showWordCount: false,
        showSource: true,
        showSeparators: false,
        emptyMessage: "No results found"
    )

    public static let mcpDefault = SearchResultFormatConfig(
        showScore: true,
        showWordCount: true,
        showSource: false,
        showSeparators: true,
        emptyMessage: "_No results found. Try broader search terms._"
    )
}
```

### 4. Format-Specific Implementations

```swift
// Sources/Services/Formatters/MarkdownFormatter.swift

public struct MarkdownSearchResultFormatter: ResultFormatter {
    private let config: SearchResultFormatConfig
    private let query: String
    private let filters: SearchFilters?

    public init(query: String, filters: SearchFilters? = nil, config: SearchResultFormatConfig = .mcpDefault) {
        self.query = query
        self.filters = filters
        self.config = config
    }

    public func format(_ results: [Search.Result]) -> String {
        var md = "# Search Results for \"\(query)\"\n\n"

        // Show active filters
        if let filters {
            if let source = filters.source {
                md += "_Filtered to source: **\(source)**_\n\n"
            }
            if let framework = filters.framework {
                md += "_Filtered to framework: **\(framework)**_\n\n"
            }
        }

        md += "Found **\(results.count)** result\(results.count == 1 ? "" : "s"):\n\n"

        if results.isEmpty {
            md += config.emptyMessage
            return md
        }

        for (index, result) in results.enumerated() {
            md += "## \(index + 1). \(result.title)\n\n"
            md += "- **Framework:** `\(result.framework)`\n"
            md += "- **URI:** `\(result.uri)`\n"

            if config.showScore {
                md += "- **Score:** \(String(format: "%.2f", result.score))\n"
            }
            if config.showWordCount {
                md += "- **Words:** \(result.wordCount)\n"
            }

            md += "\n\(result.summary)\n\n"

            if config.showSeparators && index < results.count - 1 {
                md += "---\n\n"
            }
        }

        return md
    }
}

// Sources/Services/Formatters/JSONFormatter.swift

public struct JSONSearchResultFormatter: ResultFormatter {
    public init() {}

    public func format(_ results: [Search.Result]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(results),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

// Sources/Services/Formatters/TextFormatter.swift

public struct TextSearchResultFormatter: ResultFormatter {
    private let query: String

    public init(query: String) {
        self.query = query
    }

    public func format(_ results: [Search.Result]) -> String {
        if results.isEmpty {
            return "No results found for '\(query)'"
        }

        var output = "Found \(results.count) result(s) for '\(query)':\n\n"

        for (index, result) in results.enumerated() {
            output += "[\(index + 1)] \(result.title)\n"
            output += "    Source: \(result.source) | Framework: \(result.framework)\n"
            output += "    URI: \(result.uri)\n"
            if !result.summary.isEmpty {
                output += "    \(result.summary)\n"
            }
            output += "\n"
        }

        return output
    }
}
```

### 5. Unified Tool Error

```swift
// Sources/Shared/ToolError.swift

public enum ToolError: Error, LocalizedError {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String, String)
    case notFound(String)
    case noData(String)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .missingArgument(let arg):
            return "Missing required argument: \(arg)"
        case .invalidArgument(let arg, let reason):
            return "Invalid argument '\(arg)': \(reason)"
        case .notFound(let resource):
            return "Not found: \(resource)"
        case .noData(let message):
            return message
        }
    }
}
```

### 6. Argument Extractor

```swift
// Sources/Shared/ArgumentExtractor.swift

public struct ArgumentExtractor {
    private let arguments: [String: AnyCodable]?

    public init(_ arguments: [String: AnyCodable]?) {
        self.arguments = arguments
    }

    public func require<T>(_ key: String) throws -> T {
        guard let value = arguments?[key]?.value as? T else {
            throw ToolError.missingArgument(key)
        }
        return value
    }

    public func optional<T>(_ key: String) -> T? {
        arguments?[key]?.value as? T
    }

    public func optional<T>(_ key: String, default: T) -> T {
        (arguments?[key]?.value as? T) ?? `default`
    }

    public func limit(key: String = "limit", default: Int = Constants.Limit.defaultSearchLimit) -> Int {
        let requested = optional(key, default: `default`)
        return min(requested, Constants.Limit.maxSearchLimit)
    }
}
```

---

## Refactored CLI Command Example

```swift
// Sources/CLI/Commands/SearchCommand.swift

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search Apple documentation"
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .shortAndLong, help: "Filter by source")
    var source: String?

    @Flag(name: .long, help: "Include archive docs")
    var includeArchive: Bool = false

    @Option(name: .shortAndLong, help: "Filter by framework")
    var framework: String?

    @Option(name: .shortAndLong, help: "Filter by language")
    var language: String?

    @Option(name: .long, help: "Max results")
    var limit: Int = Constants.Limit.defaultSearchLimit

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Database path")
    var searchDb: String?

    mutating func run() async throws {
        try await ServiceContainer.withDocsService(dbPath: searchDb) { service in
            let searchQuery = SearchQuery(
                text: query,
                source: source,
                framework: framework,
                language: language,
                limit: limit,
                includeArchive: includeArchive
            )

            let results = try await service.search(searchQuery)
            let output = formatter(for: format).format(results)
            Log.output(output)
        }
    }

    private func formatter(for format: OutputFormat) -> any ResultFormatter {
        switch format {
        case .text: return TextSearchResultFormatter(query: query)
        case .json: return JSONSearchResultFormatter()
        case .markdown: return MarkdownSearchResultFormatter(query: query, config: .cliDefault)
        }
    }
}
```

---

## Refactored MCP Tool Example

```swift
// Sources/SearchToolProvider/DocumentationToolProvider.swift

public actor DocumentationToolProvider: ToolProvider {
    private let docsService: DocsSearchService
    private let higService: HIGSearchService

    public init(searchIndex: Search.Index) {
        self.docsService = DocsSearchService(index: searchIndex)
        self.higService = HIGSearchService(index: searchIndex)
    }

    public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
        let args = ArgumentExtractor(arguments)

        switch name {
        case Constants.MCP.toolSearchDocs:
            let query = SearchQuery(
                text: try args.require("query"),
                source: args.optional("source"),
                framework: args.optional("framework"),
                language: args.optional("language"),
                limit: args.limit(),
                includeArchive: args.optional("include_archive", default: false)
            )
            let results = try await docsService.search(query)
            let formatter = MarkdownSearchResultFormatter(
                query: query.text,
                filters: SearchFilters(source: query.source, framework: query.framework),
                config: .mcpDefault
            )
            return CallToolResult(content: [.text(TextContent(text: formatter.format(results)))])

        case Constants.MCP.toolSearchHIG:
            let query = HIGSearchService.HIGQuery(
                text: try args.require("query"),
                platform: args.optional("platform"),
                category: args.optional("category"),
                limit: args.limit()
            )
            let results = try await higService.search(query)
            let formatter = HIGMarkdownFormatter(query: query)
            return CallToolResult(content: [.text(TextContent(text: formatter.format(results)))])

        // ... other tools
        default:
            throw ToolError.unknownTool(name)
        }
    }
}
```

---

## New Module Structure

```
Sources/
├── Services/                           # NEW MODULE
│   ├── Package.swift
│   ├── SearchService.swift             # Protocol
│   ├── DocsSearchService.swift         # Implementation
│   ├── HIGSearchService.swift          # Implementation
│   ├── SampleSearchService.swift       # Implementation
│   ├── ServiceContainer.swift          # Lifecycle management
│   └── Formatters/
│       ├── ResultFormatter.swift       # Protocol
│       ├── MarkdownFormatter.swift
│       ├── JSONFormatter.swift
│       ├── TextFormatter.swift
│       └── HIGFormatter.swift
│
├── Shared/
│   ├── ToolError.swift                 # Unified error type
│   ├── ArgumentExtractor.swift         # MCP argument helper
│   ├── PathResolver.swift              # Database path resolution
│   └── Extensions/
│       └── URL+Tilde.swift             # Tilde expansion
│
├── CLI/
│   ├── OutputFormat.swift              # Shared enum
│   └── Commands/                       # Thin wrappers
│
└── SearchToolProvider/
    ├── DocumentationToolProvider.swift # Thin wrapper
    ├── SampleCodeToolProvider.swift    # Thin wrapper
    └── CompositeToolProvider.swift     # Unchanged
```

---

## Migration Steps

### Phase 1: Extract Shared Utilities (Low Risk)
1. Move `URL.expandingTildeInPath` to `Shared/Extensions/`
2. Create `Shared/PathResolver.swift`
3. Create `Shared/ToolError.swift`
4. Create `Shared/ArgumentExtractor.swift`
5. Create `CLI/OutputFormat.swift`

### Phase 2: Create Services Module (Medium Risk)
1. Create `Services` module in Package.swift
2. Implement `SearchService` protocol
3. Implement `DocsSearchService`
4. Implement `HIGSearchService`
5. Implement `SampleSearchService`
6. Create `ServiceContainer` for lifecycle

### Phase 3: Create Formatters (Medium Risk)
1. Implement `ResultFormatter` protocol
2. Implement `MarkdownFormatter` with config
3. Implement `JSONFormatter`
4. Implement `TextFormatter`
5. Implement `HIGFormatter`

### Phase 4: Refactor CLI Commands (High Risk)
1. Update `SearchCommand` to use services
2. Update `ReadCommand` to use services
3. Update `ListFrameworksCommand` to use services
4. Update sample code commands
5. Add `SearchHIGCommand` or `--hig` flag

### Phase 5: Refactor MCP Providers (High Risk)
1. Update `DocumentationToolProvider`
2. Update `SampleCodeToolProvider`
3. Simplify `DocsResourceProvider`

---

## Benefits

| Metric | Before | After |
|--------|--------|-------|
| Error enum duplicates | 4 | 1 |
| Path resolution duplicates | 6 | 1 |
| Markdown formatting duplicates | 8+ | 3 (per format) |
| Argument extraction duplicates | 15+ | 1 helper |
| Lines to test search logic | 400+ | ~100 |
| New features (add source) | Touch 5+ files | Touch 1 service |

---

## Test Strategy

```swift
// Tests/ServicesTests/DocsSearchServiceTests.swift

@Test("Search returns results for valid query")
func testSearch() async throws {
    let index = try await TestHelpers.createTestIndex()
    let service = DocsSearchService(index: index)

    let results = try await service.search(SearchQuery(text: "View"))

    #expect(results.count > 0)
    #expect(results[0].title.contains("View"))
}

// Tests/ServicesTests/FormatterTests.swift

@Test("Markdown formatter produces valid output")
func testMarkdownFormatter() {
    let results = [TestHelpers.mockSearchResult()]
    let formatter = MarkdownSearchResultFormatter(query: "test", config: .mcpDefault)

    let output = formatter.format(results)

    #expect(output.contains("# Search Results"))
    #expect(output.contains("## 1."))
    #expect(output.contains("**Score:**"))
}
```

---

*This file can be deleted after refactoring is complete.*
