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
     crawler: Shared.CrawlerConfiguration(
         startURL: URL(string: "\(Shared.Constants.BaseURL.appleDeveloperDocs)swiftui")!,
         maxPages: 1000
     ),
     changeDetection: Shared.ChangeDetectionConfiguration(enabled: true),
     output: Shared.OutputConfiguration(format: .markdown)
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

    /// Build a `URL` from a string the caller asserts is well-formed.
    ///
    /// Use for URLs constructed from compile-time literals or from internal
    /// constants (e.g. `Shared.Constants.BaseURL.*`) interpolated with
    /// sanitized components. Equivalent to `URL(string: s)!`, but:
    ///
    /// - communicates the "known-good" contract at the call site,
    /// - crashes with a message naming the offending string and the source
    ///   location, instead of a bare "unexpectedly found nil while unwrapping
    ///   an Optional value",
    /// - localizes the force-unwrap to a single audited place.
    ///
    /// **Do not use for URLs sourced from external/runtime data** (parsed
    /// JSON, HTTP responses, indexed page metadata): a malformed string is
    /// a recoverable condition there, not a programmer error. Use plain
    /// `URL(string:)` + `guard let` in those cases.
    public static func knownGood(
        _ string: String,
        file: StaticString = #file,
        line: UInt = #line
    ) -> URL {
        guard let url = URL(string: string) else {
            fatalError("URL.knownGood: malformed URL string '\(string)'", file: file, line: line)
        }
        return url
    }
}
