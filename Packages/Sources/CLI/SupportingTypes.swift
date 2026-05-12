import ArgumentParser
import Foundation
import SharedCore
import SharedConstants

// MARK: - Supporting Types

extension Cupertino {
    enum FetchType: String, ExpressibleByArgument {
        case docs
        case swift
        case evolution
        case packages
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
            case .packages: return Shared.Constants.DisplayName.swiftPackages
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
            case .packages: return "" // API-based fetching + GitHub archive download
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

        /// Per-type default output dir. Routes through `Shared.Constants.default*`
        /// getters so the path resolves via `Shared.BinaryConfig` (#211) like
        /// every other default does. The earlier manual construction
        /// (`homeDir + baseDirectoryName + Directory.<x>`) bypassed BinaryConfig
        /// and silently wrote to `~/.cupertino/<x>` even when a binary-co-located
        /// config redirected the base elsewhere — the bug reported on
        /// 2026-05-03 against `cupertino fetch --type swift`.
        var defaultOutputDir: String {
            switch self {
            case .docs, .availability:
                return Shared.Constants.defaultDocsDirectory.path
            case .swift:
                return Shared.Constants.defaultSwiftOrgDirectory.path
            case .evolution:
                return Shared.Constants.defaultSwiftEvolutionDirectory.path
            case .packages:
                return Shared.Constants.defaultPackagesDirectory.path
            case .code, .samples:
                return Shared.Constants.defaultSampleCodeDirectory.path
            case .archive:
                return Shared.Constants.defaultArchiveDirectory.path
            case .hig:
                return Shared.Constants.defaultHIGDirectory.path
            case .all:
                return Shared.Constants.defaultBaseDirectory.path
            }
        }

        static var webCrawlTypes: [FetchType] {
            [.docs, .swift, .evolution]
        }

        static var directFetchTypes: [FetchType] {
            [.packages, .code, .samples, .archive, .hig, .availability]
        }

        static var allTypes: [FetchType] {
            webCrawlTypes + directFetchTypes
        }
    }
}
