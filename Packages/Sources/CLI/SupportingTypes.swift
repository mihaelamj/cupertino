import ArgumentParser
import Foundation
import SharedConstants
import SharedCore

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

        /// Per-type default output dir, resolved against an explicit
        /// `Shared.Paths` rather than the static `Shared.Constants.default*`
        /// accessors. The caller (a CLI command's `run()`) constructs
        /// `Shared.Paths.live()` once at its composition sub-root and
        /// passes it here — same pattern as the other live concretes
        /// from #521 / #527 / etc. The earlier manual construction
        /// (`homeDir + baseDirectoryName + Directory.<x>`) bypassed
        /// BinaryConfig and silently wrote to `~/.cupertino/<x>` even
        /// when a binary-co-located config redirected the base elsewhere
        /// — the bug reported on 2026-05-03 against `cupertino fetch
        /// --type swift`. Routing through `Shared.Paths` preserves the
        /// fix while replacing the Service-Locator-shaped static reach
        /// (#535).
        func defaultOutputDir(paths: Shared.Paths) -> String {
            switch self {
            case .docs, .availability:
                return paths.docsDirectory.path
            case .swift:
                return paths.swiftOrgDirectory.path
            case .evolution:
                return paths.swiftEvolutionDirectory.path
            case .packages:
                return paths.packagesDirectory.path
            case .code, .samples:
                return paths.sampleCodeDirectory.path
            case .archive:
                return paths.archiveDirectory.path
            case .hig:
                return paths.higDirectory.path
            case .all:
                return paths.baseDirectory.path
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
