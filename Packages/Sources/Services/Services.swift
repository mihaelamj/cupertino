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
//     let formatter = Services.Services.Formatter.Markdown(query: "View")
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

/// Namespace for the service layer.
///
/// Layout:
/// - `Services.ServiceContainer`, `Services.SearchService` protocol,
///   `Services.SearchQuery`, `Services.SearchFilters` — root-level lifecycle
///   + protocol surface.
/// - `Services.Formatter.*` — result-formatter family in
///   `Sources/Services/Formatters/`. Singular `Formatter` namespace with
///   per-variant nested types: `Services.Formatter.Result` protocol,
///   `Services.Formatter.Config`, `Services.Formatter.{Markdown,Text,JSON}`,
///   `Services.Formatter.HIG.{Markdown,Text}`,
///   `Services.Formatter.Frameworks.Markdown`,
///   `Services.Formatter.Unified.{Markdown,Text,JSON,Input}`,
///   `Services.Formatter.Footer.{Search,Item,Kind,Provider,Formattable,Markdown,Text}`,
///   `Services.Formatter.TeaserResults`.
/// - Concrete service actors in `Services/ReadCommands/`
///   (`Services.DocsSearchService`, `Services.HIGSearchService`, `Services.UnifiedSearchService`,
///   `Services.TeaserService`, `Services.ReadService`) still live at file scope and will
///   move to `Services.*` once their wrap PRs land.
///
/// Sample-flavoured services live under the cross-cutting `Sample` root:
/// `Sample.Search.Service`, `Sample.Format.{Markdown,JSON,Text}.*`,
/// `Sample.Services.CandidateFetcher`.
public enum Services {
    /// Sub-namespace for result-formatter types. Mirrors
    /// `Sources/Services/Formatters/`. Each concrete formatter conforms
    /// to `Services.Formatter.Result`.
    public enum Formatter {
        /// HIG (Human Interface Guidelines) formatter variants.
        public enum HIG {}
        /// Frameworks-list formatter variants.
        public enum Frameworks {}
        /// Unified-search formatter variants.
        public enum Unified {}
        /// Footer-rendering family (kind / item / provider / formatter pair).
        public enum Footer {}
    }
}
