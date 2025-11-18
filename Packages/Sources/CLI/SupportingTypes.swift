import ArgumentParser
import Foundation
import Shared

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
            case .docs: return Shared.Constants.DisplayName.appleDocs
            case .swift: return Shared.Constants.DisplayName.swiftOrgDocs
            case .evolution: return Shared.Constants.DisplayName.swiftEvolution
            case .packages: return Shared.Constants.DisplayName.swiftPackages
            case .all: return Shared.Constants.DisplayName.allDocs
            }
        }

        var defaultURL: String {
            switch self {
            case .docs: return Shared.Constants.BaseURL.appleDeveloperDocs
            case .swift: return Shared.Constants.BaseURL.swiftBook
            case .evolution: return "" // N/A - uses different crawler
            case .packages: return "" // Package documentation not yet implemented
            case .all: return "" // N/A - crawls all types sequentially
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
            case .packages: return Shared.Constants.DisplayName.packageMetadata
            case .code: return Shared.Constants.DisplayName.sampleCode
            }
        }
    }
}
