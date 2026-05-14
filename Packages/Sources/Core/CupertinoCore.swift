// MARK: - CupertinoCore Package

//
// Core crawler implementation for Apple Documentation.
// Uses WKWebView for page loading and HTML→Markdown conversion.
//
// Depends on: CupertinoShared
// Platform: macOS only (requires WebKit)

#if canImport(WebKit)
@_exported import WebKit
#endif

import SharedConstants
// SharedCore was absorbed into SharedConstants in #536 phase 1a. The
// `@_exported` here was reaching for the SharedCore module surface;
// now that surface is part of SharedConstants which is already imported above.

// MARK: - Usage Example

/*
 // Create configuration
 let config = Shared.Configuration(
     crawler: Shared.Configuration.Crawler(
         startURL: URL(string: "\(Shared.Constants.BaseURL.appleDeveloperDocs)swiftui")!,
         maxPages: 100
     )
 )

 // Create and run crawler
 let crawler = await Core.Crawler(configuration: config)

 let stats = try await crawler.crawl { progress in
     print("Progress: \(progress.percentage)% - \(progress.currentURL)")
 }

 print("Crawled \(stats.totalPages) pages")
 print("New: \(stats.newPages), Updated: \(stats.updatedPages), Skipped: \(stats.skippedPages)")
 */
