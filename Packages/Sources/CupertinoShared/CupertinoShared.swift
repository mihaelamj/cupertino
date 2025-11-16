// MARK: - CupertinoShared Package

//
// Shared models, configuration, and utilities for Apple Documentation crawler.
// Foundation layer package for Cupertino application.
//
// Depends on: MCPShared (for resource types)

@_exported import Foundation
@_exported import MCPShared

// Re-export CryptoKit for hashing utilities
@_exported import CryptoKit

// MARK: - Usage Example

/*
 // Create configuration
 let config = CupertinoConfiguration(
     crawler: CrawlerConfiguration(
         startURL: URL(string: "\(CupertinoConstants.BaseURL.appleDeveloperDocs)swiftui")!,
         maxPages: 1000
     ),
     changeDetection: ChangeDetectionConfiguration(enabled: true),
     output: OutputConfiguration(format: .markdown)
 )

 // Save configuration
 let configURL = CupertinoConstants.defaultConfigFile
 try config.save(to: configURL)

 // Create metadata tracker
 var metadata = CrawlMetadata()

 // Add page
 let exampleURL = "\(CupertinoConstants.BaseURL.appleDeveloperDocs)swiftui/view"
 metadata.pages[exampleURL] = PageMetadata(
     url: exampleURL,
     framework: "swiftui",
     filePath: CupertinoConstants.defaultDocsDirectory.appendingPathComponent("swiftui/view.md").path,
     contentHash: HashUtilities.sha256(of: "content"),
     depth: 1
 )

 // Save metadata
 let metadataURL = CupertinoConstants.defaultMetadataFile
 try metadata.save(to: metadataURL)
 */

// MARK: - URL Extension for Tilde Expansion

extension URL {
    /// Expand tilde (~) in file paths
    public var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let relativePath = String(path.dropFirst(2)) // Remove "~/"
            return homeDirectory.appendingPathComponent(relativePath)
        }
        return self
    }
}
