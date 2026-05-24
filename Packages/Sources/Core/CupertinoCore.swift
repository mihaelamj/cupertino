// MARK: - CupertinoCore Package

//
// Core crawler implementation for Apple Documentation. Foundation-only
// post-#904: WebKit-backed concretes live in `CoreJSONParserWebKit` +
// `CoreSampleCodeWebKit` sibling targets.
//
// Depends on: SharedConstants.

import SharedConstants

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
