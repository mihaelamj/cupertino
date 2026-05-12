// MARK: - Services Module

//
// The Services module provides a unified service layer for search operations.
// It abstracts database access and result formatting, allowing both CLI
// commands and MCP tool providers to share the same business logic.
//
// Usage:
//
// ```swift
// // Using ServiceContainer for managed lifecycle
// try await Services.ServiceContainer.withDocsService { service in
//     let results = try await service.search(text: "View")
//     let formatter = Services.MarkdownSearchResultFormatter(query: "View")
//     print(formatter.format(results))
// }
//
// // Or create services directly
// let service = try await Services.DocsSearchService(dbPath: dbPath)
// defer { Task { await service.disconnect() } }
//
// let results = try await service.search(Services.SearchQuery(text: "SwiftUI"))
// ```

@_exported import Foundation

// MARK: - Services Namespace

/// Namespace for the service layer: a `ServiceContainer` that owns service
/// lifecycle, the `SearchService` protocol + `SearchQuery` / `SearchFilters`
/// inputs, and the concrete service actors that live in `Services/ReadCommands/`
/// (`DocsSearchService`, `HIGSearchService`, `SampleSearchService`,
/// `UnifiedSearchService`, `TeaserService`, `ReadService`).
///
/// Result formatters in `Services/Formatters/` also extend this same root
/// (`Services.MarkdownSearchResultFormatter`, `Services.JSONSearchResultFormatter`,
/// `Services.TextSearchResultFormatter`, etc.).
public enum Services {}
