import ArgumentParser
import Foundation
import Logging
import Shared

// MARK: - Global Options

/// Options shared across all commands
struct GlobalOptions: ParsableArguments {
    @Flag(name: [.short, .long], help: "Enable verbose output with detailed progress information")
    var verbose: Bool = false

    /// Configure logging based on verbose flag
    func configureLogging() {
        Logging.ConsoleLogger.isVerbose = verbose
    }
}

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
        case hig
        case availability
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
            case .hig: return Shared.Constants.DisplayName.humanInterfaceGuidelines
            case .availability: return "API Availability Data"
            case .all: return Shared.Constants.DisplayName.allDocs
            }
        }

        var defaultURL: String {
            switch self {
            case .docs: return Shared.Constants.BaseURL.appleDeveloperDocs
            case .swift: return Shared.Constants.BaseURL.swiftOrg
            case .evolution: return "" // N/A - uses different fetcher
            case .packages: return "" // API-based fetching
            case .packageDocs: return "" // GitHub raw content downloading
            case .code: return "" // Web-based download from Apple
            case .samples: return "" // Git clone from GitHub
            case .archive: return Shared.Constants.BaseURL.appleArchive
            case .hig: return Shared.Constants.BaseURL.appleHIG
            case .availability: return "" // Updates existing docs
            case .all: return "" // N/A - fetches all types sequentially
            }
        }

        var defaultAllowedPrefixes: [String]? {
            switch self {
            case .swift:
                // Swift docs span both www.swift.org and docs.swift.org (swift-book)
                return [
                    Shared.Constants.BaseURL.swiftOrg,
                    Shared.Constants.BaseURL.swiftBook,
                ]
            default:
                return nil // Auto-detect from start URL
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
            case .hig:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.hig)"
            case .availability:
                return "\(homeDir)/\(baseDir)/\(Shared.Constants.Directory.docs)"
            case .all:
                return "\(homeDir)/\(baseDir)"
            }
        }

        static var webCrawlTypes: [FetchType] {
            [.docs, .swift, .evolution]
        }

        static var directFetchTypes: [FetchType] {
            [.packages, .packageDocs, .code, .samples, .archive, .hig, .availability]
        }

        static var allTypes: [FetchType] {
            webCrawlTypes + directFetchTypes
        }
    }
}
