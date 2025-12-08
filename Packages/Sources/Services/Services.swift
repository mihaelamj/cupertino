// MARK: - Services Module

//
// The Services module provides a unified service layer for search operations.
// It abstracts database access and result formatting, allowing both CLI commands
// and MCP tool providers to share the same business logic.
//
// Usage:
//
// ```swift
// // Using ServiceContainer for managed lifecycle
// try await ServiceContainer.withDocsService { service in
//     let results = try await service.search(text: "View")
//     let formatter = MarkdownSearchResultFormatter(query: "View")
//     print(formatter.format(results))
// }
//
// // Or create services directly
// let service = try await DocsSearchService(dbPath: dbPath)
// defer { Task { await service.disconnect() } }
//
// let results = try await service.search(SearchQuery(text: "SwiftUI"))
// ```

@_exported import Foundation
