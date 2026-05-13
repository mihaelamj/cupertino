// MARK: - CupertinoShared Package

//
// Shared models, configuration, and utilities for Apple Documentation crawler.
// Foundation layer package for Cupertino application.
//

@_exported import Foundation

// Re-export CryptoKit for hashing utilities
@_exported import CryptoKit

// MARK: - Usage Example

/*
 // Create configuration
 let config = Shared.Configuration(
     crawler: Shared.Configuration.Crawler(
         startURL: URL(string: "\(Shared.Constants.BaseURL.appleDeveloperDocs)swiftui")!,
         maxPages: 1000
     ),
     changeDetection: Shared.Configuration.ChangeDetection(enabled: true),
     output: Shared.Configuration.Output(format: .markdown)
 )

 // Save configuration
 let configURL = Shared.Constants.defaultConfigFile
 try config.save(to: configURL)

 // Create metadata tracker
 var metadata = CrawlMetadata()

 // Add page
 let exampleURL = "\(Shared.Constants.BaseURL.appleDeveloperDocs)swiftui/view"
 metadata.pages[exampleURL] = PageMetadata(
     url: exampleURL,
     framework: "swiftui",
     filePath: Shared.Constants.defaultDocsDirectory.appendingPathComponent("swiftui/view.md").path,
     contentHash: HashUtilities.sha256(of: "content"),
     depth: 1
 )

 // Save metadata
 let metadataURL = Shared.Constants.defaultMetadataFile
 try metadata.save(to: metadataURL)
 */

// URL extensions (`expandingTildeInPath`, `knownGood`) moved to
// `SharedUtils/URLExtensions.swift` in task 1.4. Callers that
// `import Shared` continue to see them through `Shared/Exports.swift`'s
// `@_exported import SharedUtils`.
