// MARK: - DocsuckerShared Package
//
// Shared models, configuration, and utilities for Apple Documentation crawler.
// Foundation layer package for Docsucker application.
//
// Depends on: MCPShared (for resource types)

@_exported import Foundation
@_exported import MCPShared

// Re-export CryptoKit for hashing utilities
@_exported import CryptoKit

// MARK: - Usage Example
/*
 // Create configuration
 let config = DocsuckerConfiguration(
     crawler: CrawlerConfiguration(
         startURL: URL(string: "https://developer.apple.com/documentation/swiftui")!,
         maxPages: 1000
     ),
     changeDetection: ChangeDetectionConfiguration(enabled: true),
     output: OutputConfiguration(format: .markdown)
 )

 // Save configuration
 let configURL = URL(fileURLWithPath: "~/.docsucker/config.json").expandingTildeInPath
 try config.save(to: configURL)

 // Create metadata tracker
 var metadata = CrawlMetadata()

 // Add page
 metadata.pages["https://developer.apple.com/documentation/swiftui/view"] = PageMetadata(
     url: "https://developer.apple.com/documentation/swiftui/view",
     framework: "swiftui",
     filePath: "~/.docsucker/docs/swiftui/view.md",
     contentHash: HashUtilities.sha256(of: "content"),
     depth: 1
 )

 // Save metadata
 let metadataURL = URL(fileURLWithPath: "~/.docsucker/metadata.json").expandingTildeInPath
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
