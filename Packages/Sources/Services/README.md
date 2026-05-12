# Services Module

The Services module provides a unified service layer for search operations across documentation sources. It abstracts database access and result formatting, allowing both CLI commands and MCP tool providers to share the same business logic.

All public types now live under the `Services` namespace (per the namespacing sweep tracked in #183). Sample-flavoured services live under the cross-cutting `Sample` namespace: the sample search service is `Sample.Search.Service`, the sample-flavoured formatters live under `Sample.Format.{Markdown,JSON,Text}.*`, and the sample-flavoured candidate fetcher is `Sample.Services.CandidateFetcher`.

## Architecture

```
                       ┌──────────────────────────────┐
                       │  Services.ServiceContainer   │
                       │      (Lifecycle Mgmt)        │
                       └──────────────┬───────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        │                             │                             │
        ▼                             ▼                             ▼
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────────┐
│ DocsSearchService│         │  HIGSearchService│         │ Sample.Search.Service│
│   (Search.Index) │         │    (delegates)   │         │     (Sample.Index)   │
└──────────────────┘         └──────────────────┘         └──────────────────────┘
        │                             │                             │
        └─────────────────────────────┼─────────────────────────────┘
                                      │
                                      ▼
                       ┌──────────────────────────────┐
                       │     Services.Formatters      │
                       │ + Sample.Format.{Md,JSON,Txt}│
                       │      (Text/JSON/Markdown)    │
                       └──────────────────────────────┘
```

## Services

### DocsSearchService

Wraps `Search.Index` for searching Apple documentation, Swift Evolution proposals, Swift.org docs, and more. Currently still at file scope inside the `Services` SPM target; will move to `Services.DocsSearchService` once the `Services/ReadCommands/` type-wrap PR lands.

```swift
let service = try await DocsSearchService(dbPath: dbPath)

// Simple search
let results = try await service.search(text: "View")

// Search with filters
let results = try await service.search(Services.SearchQuery(
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

### Sample.Search.Service

Wraps `Sample.Index.Database` for searching Apple sample code projects and files. Lives under the cross-cutting `Sample` namespace alongside `Sample.Search.Query` and `Sample.Search.Result`.

```swift
let service = try await Sample.Search.Service(dbPath: dbPath)

// Search projects and files
let result = try await service.search(Sample.Search.Query(
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

## Services.ServiceContainer

Manages service lifecycle with convenient factory methods.

```swift
// Managed lifecycle — service automatically disconnected
try await Services.ServiceContainer.withDocsService { service in
    let results = try await service.search(text: "Actor")
    return results
}

// HIG service with managed lifecycle
try await Services.ServiceContainer.withHIGService { service in
    let results = try await service.search(text: "buttons")
    return results
}

// Sample service with managed lifecycle
try await Services.ServiceContainer.withSampleService(dbPath: sampleDbPath) { service in
    let results = try await service.search(text: "SwiftUI")
    return results
}
```

## Query Types

### Services.SearchQuery

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

Specialized query for Human Interface Guidelines (file-scope today; will move to `Services.HIGQuery` in the `Services/ReadCommands/` wrap PR).

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `text` | `String` | required | Search text |
| `platform` | `String?` | `nil` | iOS, macOS, watchOS, visionOS, tvOS |
| `category` | `String?` | `nil` | foundations, patterns, components, etc. |
| `limit` | `Int` | 20 | Max results |

### Sample.Search.Query

Query for sample code searches.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `text` | `String` | required | Search text |
| `framework` | `String?` | `nil` | Filter by framework |
| `searchFiles` | `Bool` | `true` | Also search file contents |
| `limit` | `Int` | 20 | Max results |

## Formatters

`Services/Formatters/*` ships two formatter families:

- The `Services.Formatters.*` family (general-purpose `MarkdownSearchResultFormatter`, `TextSearchResultFormatter`, `JSONSearchResultFormatter`, `Frameworks*Formatter`, HIG-specific, unified-search) — wrap pass in progress; type names still flat at file scope for now.
- The `Sample.Format.{Markdown,JSON,Text}.*` family (`Search` / `List` / `Project` / `File` per medium), already nested under the cross-cutting `Sample` namespace (#362).

### Services.Formatters.MarkdownSearchResultFormatter

Formats search results as markdown for MCP tools.

```swift
let formatter = Services.Formatters.MarkdownSearchResultFormatter(
    query: "View",
    filters: Services.SearchFilters(framework: "swiftui"),
    config: .mcpDefault
)
let markdown = formatter.format(results)
```

### Services.Formatters.TextSearchResultFormatter

Formats search results as plain text for CLI output.

```swift
let formatter = Services.Formatters.TextSearchResultFormatter(query: "View")
let text = formatter.format(results)
```

### Services.Formatters.JSONSearchResultFormatter

Formats search results as JSON.

```swift
let formatter = Services.Formatters.JSONSearchResultFormatter()
let json = formatter.format(results)
```

### Format Configuration

```swift
// CLI defaults: no score/word count, show source, no separators
let cliConfig = Services.Formatters.SearchResultFormatConfig.cliDefault

// MCP defaults: show score/word count, separators between results
let mcpConfig = Services.Formatters.SearchResultFormatConfig.mcpDefault

// Custom configuration
let config = Services.Formatters.SearchResultFormatConfig(
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
├── Shared           (Shared.Core.ToolError, Shared.Utils.PathResolver, Shared.Constants)
├── Search           (Search.Index, Search.Result, Search.SmartQuery, Search.PackageQuery)
└── SampleIndex      (Sample.Index.Database, Sample.Index.Project, Sample.Index.File)
```

## Design Principles

1. **Single Responsibility**: Each service wraps one database type
2. **Composition**: `HIGSearchService` delegates to `DocsSearchService`
3. **Lifecycle Management**: `Services.ServiceContainer` handles connections
4. **Type Safety**: Specialized query types for each search domain (`Services.SearchQuery`, `Services.HIGQuery`, `Sample.Search.Query`)
5. **Flexibility**: Formatters separate output from business logic (`Services.Formatters.*` for general, `Sample.Format.*` for sample-specific)
