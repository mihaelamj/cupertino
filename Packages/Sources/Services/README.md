# Services Module

The Services module provides a unified service layer for search operations across documentation sources. It abstracts database access and result formatting, allowing both CLI commands and MCP tool providers to share the same business logic.

## Architecture

```
                     ┌─────────────────────┐
                     │  ServiceContainer   │
                     │  (Lifecycle Mgmt)   │
                     └─────────┬───────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
       ▼                       ▼                       ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│DocsSearchSvc │      │ HIGSearchSvc │      │SampleSearchSvc│
│ (Search.Index)│      │  (delegates) │      │ (SampleIndex) │
└──────────────┘      └──────────────┘      └──────────────┘
       │                       │                       │
       └───────────────────────┼───────────────────────┘
                               │
                               ▼
                     ┌─────────────────────┐
                     │     Formatters      │
                     │ (Text/JSON/Markdown)│
                     └─────────────────────┘
```

## Services

### DocsSearchService

Wraps `Search.Index` for searching Apple documentation, Swift Evolution proposals, Swift.org docs, and more.

```swift
let service = try await DocsSearchService(dbPath: dbPath)

// Simple search
let results = try await service.search(text: "View")

// Search with filters
let results = try await service.search(SearchQuery(
    text: "Button",
    source: "apple-docs",
    framework: "swiftui",
    limit: 25
))

// Read document content
let content = try await service.read(uri: "apple-docs://swiftui/view", format: .json)

// List frameworks
let frameworks = try await service.listFrameworks()

await service.disconnect()
```

### HIGSearchService

Specialized service for Human Interface Guidelines with platform and category filtering.

```swift
let service = HIGSearchService(docsService: docsService)

// Simple HIG search
let results = try await service.search(text: "buttons")

// Search with platform filter
let results = try await service.search(HIGQuery(
    text: "navigation",
    platform: "iOS",
    category: "patterns",
    limit: 20
))

await service.disconnect()
```

### SampleSearchService

Wraps `SampleIndex.Database` for searching Apple sample code projects and files.

```swift
let service = try await SampleSearchService(dbPath: dbPath)

// Search projects and files
let result = try await service.search(SampleQuery(
    text: "SwiftUI",
    framework: "swiftui",
    searchFiles: true,
    limit: 20
))

// Access results
for project in result.projects {
    print(project.title)
}

// Get project details
let project = try await service.getProject(id: "NavigatingHierarchicalData")

// Get file content
let file = try await service.getFile(projectId: projectId, path: "ContentView.swift")

await service.disconnect()
```

## ServiceContainer

Manages service lifecycle with convenient factory methods.

```swift
// Managed lifecycle - service automatically disconnected
try await ServiceContainer.withDocsService { service in
    let results = try await service.search(text: "Actor")
    return results
}

// HIG service with managed lifecycle
try await ServiceContainer.withHIGService { service in
    let results = try await service.search(text: "buttons")
    return results
}

// Sample service with managed lifecycle
try await ServiceContainer.withSampleService(dbPath: sampleDbPath) { service in
    let results = try await service.search(text: "SwiftUI")
    return results
}
```

## Query Types

### SearchQuery

General-purpose query for documentation searches.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `text` | `String` | required | Search text |
| `source` | `String?` | `nil` | Filter by source (apple-docs, swift-evolution, etc.) |
| `framework` | `String?` | `nil` | Filter by framework |
| `language` | `String?` | `nil` | Filter by language (swift, objc) |
| `limit` | `Int` | 20 | Max results (clamped to 100) |
| `includeArchive` | `Bool` | `false` | Include Apple Archive docs |

### HIGQuery

Specialized query for Human Interface Guidelines.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `text` | `String` | required | Search text |
| `platform` | `String?` | `nil` | iOS, macOS, watchOS, visionOS, tvOS |
| `category` | `String?` | `nil` | foundations, patterns, components, etc. |
| `limit` | `Int` | 20 | Max results |

### SampleQuery

Query for sample code searches.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `text` | `String` | required | Search text |
| `framework` | `String?` | `nil` | Filter by framework |
| `searchFiles` | `Bool` | `true` | Also search file contents |
| `limit` | `Int` | 20 | Max results |

## Formatters

### MarkdownSearchResultFormatter

Formats search results as markdown for MCP tools.

```swift
let formatter = MarkdownSearchResultFormatter(
    query: "View",
    filters: SearchFilters(framework: "swiftui"),
    config: .mcpDefault
)
let markdown = formatter.format(results)
```

### TextSearchResultFormatter

Formats search results as plain text for CLI output.

```swift
let formatter = TextSearchResultFormatter(query: "View")
let text = formatter.format(results)
```

### JSONSearchResultFormatter

Formats search results as JSON.

```swift
let formatter = JSONSearchResultFormatter()
let json = formatter.format(results)
```

### Format Configuration

```swift
// CLI defaults: no score/word count, show source, no separators
let cliConfig = SearchResultFormatConfig.cliDefault

// MCP defaults: show score/word count, separators between results
let mcpConfig = SearchResultFormatConfig.mcpDefault

// Custom configuration
let config = SearchResultFormatConfig(
    showScore: true,
    showWordCount: false,
    showSource: true,
    showSeparators: true,
    emptyMessage: "No results found"
)
```

## Dependencies

```
Services
├── Shared (ToolError, PathResolver, Constants)
├── Search (Search.Index, Search.Result)
└── SampleIndex (Database, Project, File)
```

## Design Principles

1. **Single Responsibility**: Each service wraps one database type
2. **Composition**: HIGSearchService delegates to DocsSearchService
3. **Lifecycle Management**: ServiceContainer handles connections
4. **Type Safety**: Specialized query types for each search domain
5. **Flexibility**: Formatters separate output from business logic
