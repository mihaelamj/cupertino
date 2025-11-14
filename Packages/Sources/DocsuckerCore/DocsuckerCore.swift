// MARK: - DocsuckerCore Package
//
// Core crawler implementation for Apple Documentation.
// Uses WKWebView for page loading and HTML→Markdown conversion.
//
// Depends on: DocsuckerShared
// Platform: macOS only (requires WebKit)

#if canImport(WebKit)
@_exported import WebKit
#endif

@_exported import DocsuckerShared

// MARK: - Usage Example
/*
 // Create configuration
 let config = DocsuckerConfiguration(
     crawler: CrawlerConfiguration(
         startURL: URL(string: "https://developer.apple.com/documentation/swiftui")!,
         maxPages: 100
     )
 )

 // Create and run crawler
 let crawler = await DocumentationCrawler(configuration: config)

 let stats = try await crawler.crawl { progress in
     print("Progress: \(progress.percentage)% - \(progress.currentURL)")
 }

 print("Crawled \(stats.totalPages) pages")
 print("New: \(stats.newPages), Updated: \(stats.updatedPages), Skipped: \(stats.skippedPages)")
 */
