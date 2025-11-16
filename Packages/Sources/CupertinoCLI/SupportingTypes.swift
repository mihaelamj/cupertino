import ArgumentParser
import CupertinoShared
import Foundation

// MARK: - Supporting Types

extension Cupertino {
    enum CrawlType: String, ExpressibleByArgument {
        case docs
        case swift
        case evolution
        case packages
        case all

        var displayName: String {
            switch self {
            case .docs: return "Apple Documentation"
            case .swift: return "Swift.org Documentation"
            case .evolution: return "Swift Evolution Proposals"
            case .packages: return "Swift Package Documentation"
            case .all: return "All Documentation"
            }
        }

        var defaultURL: String {
            switch self {
            case .docs: return CupertinoConstants.BaseURL.appleDeveloperDocs
            case .swift: return CupertinoConstants.BaseURL.swiftBook
            case .evolution: return "" // N/A - uses different crawler
            case .packages: return "" // Package documentation not yet implemented
            case .all: return "" // N/A - crawls all types sequentially
            }
        }

        var defaultOutputDir: String {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let baseDir = CupertinoConstants.baseDirectoryName
            switch self {
            case .docs:
                return "\(homeDir)/\(baseDir)/\(CupertinoConstants.Directory.docs)"
            case .swift:
                return "\(homeDir)/\(baseDir)/\(CupertinoConstants.Directory.swiftOrg)"
            case .evolution:
                return "\(homeDir)/\(baseDir)/\(CupertinoConstants.Directory.swiftEvolution)"
            case .packages:
                return "\(homeDir)/\(baseDir)/\(CupertinoConstants.Directory.packages)"
            case .all:
                return "\(homeDir)/\(baseDir)"
            }
        }

        static var allTypes: [CrawlType] {
            [.docs, .swift, .evolution]
        }
    }

    enum FetchType: String, ExpressibleByArgument {
        case packages
        case code

        var displayName: String {
            switch self {
            case .packages: return "Swift Package Metadata"
            case .code: return "Apple Sample Code"
            }
        }
    }
}
