import ArgumentParser
import Foundation
import Shared

// MARK: - Supporting Types

extension Cupertino {
    enum FetchType: String, ExpressibleByArgument {
        case docs
        case swift
        case evolution
        case packages
        case packageDocs = "package-docs"
        case code
        case samples
        case archive
        case all

        var displayName: String {
            switch self {
            case .docs: return Shared.Constants.DisplayName.appleDocs
            case .swift: return Shared.Constants.DisplayName.swiftOrgDocs
            case .evolution: return Shared.Constants.DisplayName.swiftEvolution
            case .packages: return Shared.Constants.DisplayName.packageMetadata
            case .packageDocs: return Shared.Constants.DisplayName.swiftPackages
            case .code: return Shared.Constants.DisplayName.sampleCode
            case .samples: return "Sample Code (GitHub)"
            case .archive: return Shared.Constants.DisplayName.archive
            case .all: return Shared.Constants.DisplayName.allDocs
            }
        }

        var defaultURL: String {
            switch self {
            case .docs: return Shared.Constants.BaseURL.appleDeveloperDocs
            case .swift: return Shared.Constants.BaseURL.swiftBook
            case .evolution: return "" // N/A - uses different fetcher
            case .packages: return "" // API-based fetching
            case .packageDocs: return "" // GitHub raw content downloading
            case .code: return "" // Web-based download from Apple
            case .samples: return "" // Git clone from GitHub
            case .archive: return Shared.Constants.BaseURL.appleArchive
            case .all: return "" // N/A - fetches all types sequentially
            }
        }

        var defaultOutputDir: String {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let baseDir = Shared.Constants.baseDirectoryName
            switch self {
            case .docs:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.docs)"
            case .swift:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.swiftOrg)"
            case .evolution:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.swiftEvolution)"
            case .packages:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.packages)"
            case .packageDocs:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.packages)"
            case .code:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.sampleCode)"
            case .samples:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.sampleCode)"
            case .archive:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.archive)"
            case .all:
                return "\(homeDir)/\(baseDir)"
            }
        }

        static var webCrawlTypes: [FetchType] {
            [.docs, .swift, .evolution]
        }

        static var directFetchTypes: [FetchType] {
            [.packages, .packageDocs, .code, .samples, .archive]
        }

        static var allTypes: [FetchType] {
            webCrawlTypes + directFetchTypes
        }
    }
}
