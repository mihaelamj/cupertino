import Foundation
import Logging
import SharedCore
import SharedModels

// MARK: - Package Documentation Downloader

/// Narrow helper for fetching individual README files and detecting known hosted
/// documentation sites. Kept for backward compatibility with existing integration
/// tests; the main `cupertino fetch --type packages` pipeline now goes through
/// `PackageArchiveExtractor` + `Search.PackageIndex` directly and does not call
/// any method on this type.
extension Core {
    public actor PackageDocumentationDownloader {
        private let outputDirectory: URL

        public init(outputDirectory: URL) {
            self.outputDirectory = outputDirectory
        }

        // MARK: - README Download

        /// Download README.md from GitHub. Tries main, then master; tries `README.md`,
        /// `README.MD`, `readme.md`, `Readme.md`.
        public func downloadREADME(
            owner: String,
            repo: String
        ) async throws -> String {
            guard isValidGitHubIdentifier(owner),
                  isValidGitHubIdentifier(repo) else {
                throw PackageDownloadError.invalidInput
            }

            let readmeNames = ["README.md", "README.MD", "readme.md", "Readme.md"]
            let branches = ["main", "master"]

            for branch in branches {
                for readmeName in readmeNames {
                    do {
                        let urlString = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(readmeName)"
                        guard let url = URL(string: urlString) else { continue }
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse else { continue }
                        if httpResponse.statusCode == 200,
                           let content = String(data: data, encoding: .utf8) {
                            return content
                        }
                    } catch {
                        continue
                    }
                }
            }

            throw PackageDownloadError.readmeNotFound
        }

        // MARK: - Documentation Site Detection

        public func detectDocumentationSite(
            owner: String,
            repo: String
        ) async -> DocumentationSite? {
            struct KnownSite {
                let owner: String
                let repo: String
                let url: String
                let type: DocumentationSite.DocumentationType
            }

            let knownSites = [
                KnownSite(owner: "vapor", repo: "vapor", url: "https://docs.vapor.codes", type: .customDomain),
                KnownSite(owner: "hummingbird-project", repo: "hummingbird", url: "https://docs.hummingbird.codes", type: .customDomain),
                KnownSite(owner: "apple", repo: "swift-nio", url: "https://swiftpackageindex.com/apple/swift-nio/main/documentation", type: .githubPages),
                KnownSite(owner: "apple", repo: "swift-collections", url: "https://swiftpackageindex.com/apple/swift-collections/main/documentation", type: .githubPages),
                KnownSite(owner: "apple", repo: "swift-algorithms", url: "https://swiftpackageindex.com/apple/swift-algorithms/main/documentation", type: .githubPages),
            ]

            for site in knownSites {
                if owner.lowercased() == site.owner.lowercased(),
                   repo.lowercased() == site.repo.lowercased(),
                   let url = URL(string: site.url) {
                    return DocumentationSite(type: site.type, baseURL: url)
                }
            }

            if let githubPagesURL = URL(string: "https://\(owner).github.io/\(repo)/") {
                if await urlExists(githubPagesURL) {
                    return DocumentationSite(type: .githubPages, baseURL: githubPagesURL)
                }
            }

            return nil
        }

        // MARK: - Helpers

        private func urlExists(_ url: URL) async -> Bool {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 5
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    return (200...299).contains(httpResponse.statusCode)
                }
                return false
            } catch {
                return false
            }
        }

        private func isValidGitHubIdentifier(_ identifier: String) -> Bool {
            // GitHub identifier rules (conservative union of owner + repo): alphanumeric
            // + "-_.". `.` is valid in repo names (e.g. jmespath.swift); owners use only
            // alphanumeric + hyphen in practice, but allowing `.` here is safe because
            // `..` is still rejected and `/` can't appear.
            let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
            return identifier.rangeOfCharacter(from: allowedCharacters.inverted) == nil
                && !identifier.isEmpty
                && !identifier.contains("..")
                && !identifier.hasPrefix("/")
                && !identifier.hasPrefix(".")
                && !identifier.hasSuffix(".")
        }
    }
}

// MARK: - Errors

public enum PackageDownloadError: Error, LocalizedError {
    case readmeNotFound
    case invalidInput
    case networkError(Error)
    case fileSystemError(Error)

    public var errorDescription: String? {
        switch self {
        case .readmeNotFound:
            return "README.md not found in repository"
        case .invalidInput:
            return "Invalid owner or repository name"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case let .fileSystemError(error):
            return "File system error: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .readmeNotFound:
            return "The repository may not have a README.md file"
        case .invalidInput:
            return "Owner and repository names must contain only alphanumeric characters, hyphens, and underscores"
        case .networkError:
            return "Check your internet connection and try again"
        case .fileSystemError:
            return "Check disk space and file permissions"
        }
    }
}
