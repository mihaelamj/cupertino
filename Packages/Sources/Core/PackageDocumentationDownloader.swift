import Foundation
import Logging
import Shared

// MARK: - Package Documentation Downloader

/// Downloads documentation for Swift packages (READMEs and hosted docs)
extension Core {
    public actor PackageDocumentationDownloader {
        private let outputDirectory: URL

        public init(outputDirectory: URL) {
            self.outputDirectory = outputDirectory
        }

        // MARK: - Public API

        /// Download documentation for a list of packages
        public func download(
            packages: [PackageReference],
            onProgress: (@Sendable (PackageDownloadProgress) -> Void)? = nil
        ) async throws -> PackageDownloadStatistics {
            var stats = PackageDownloadStatistics(
                totalPackages: packages.count,
                startTime: Date()
            )

            logInfo("📦 Downloading documentation for \(packages.count) packages...")

            for (index, package) in packages.enumerated() {
                let packageName = "\(package.owner)/\(package.repo)"

                // Report progress
                let progress = PackageDownloadProgress(
                    currentPackage: packageName,
                    completed: index,
                    total: packages.count,
                    status: "Downloading README"
                )
                onProgress?(progress)

                // Log progress periodically
                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    let percent = String(format: "%.1f", progress.percentage)
                    logInfo("📊 Progress: \(percent)% (\(index + 1)/\(packages.count))")
                }

                do {
                    // Check if README already exists (for new vs updated tracking)
                    let packageDir = outputDirectory
                        .appendingPathComponent(package.owner)
                        .appendingPathComponent(package.repo)
                    let readmePath = packageDir.appendingPathComponent("README.md")
                    let isNew = !FileManager.default.fileExists(atPath: readmePath.path)

                    // Download README.md
                    let readme = try await downloadREADME(
                        owner: package.owner,
                        repo: package.repo
                    )

                    // Save README to disk
                    try await saveREADME(
                        readme,
                        owner: package.owner,
                        repo: package.repo
                    )

                    // Track new vs updated
                    if isNew {
                        stats.newREADMEs += 1
                        logInfo("  ✅ \(packageName) - New README saved")
                    } else {
                        stats.updatedREADMEs += 1
                        logInfo("  ♻️  \(packageName) - README updated")
                    }

                    // Check for documentation site
                    if let site = await detectDocumentationSite(
                        owner: package.owner,
                        repo: package.repo
                    ) {
                        logInfo("  📚 Found documentation site: \(site.baseURL)")
                        // Note: Full documentation site downloading will be implemented
                        // in a future enhancement. Currently detects sites for visibility.
                    }

                } catch {
                    stats.errors += 1
                    logError("  ✗ \(packageName) - \(error.localizedDescription)")
                }

                // Priority-based rate limiting (matches PackageFetcher pattern)
                if index < packages.count - 1 {
                    try await applyRateLimit(for: package, at: index)
                }
            }

            stats.endTime = Date()

            logInfo("\n✅ Download completed!")
            logInfo("   Total packages: \(stats.totalPackages)")
            logInfo("   New READMEs: \(stats.newREADMEs)")
            logInfo("   Updated READMEs: \(stats.updatedREADMEs)")
            logInfo("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                logInfo("   Duration: \(Int(duration))s")
            }

            return stats
        }

        // MARK: - README Download

        /// Download README.md from GitHub
        public func downloadREADME(
            owner: String,
            repo: String
        ) async throws -> String {
            // Validate input to prevent path traversal
            guard isValidGitHubIdentifier(owner),
                  isValidGitHubIdentifier(repo) else {
                throw PackageDownloadError.invalidInput
            }

            // Try multiple README variants and branches
            let readmeNames = ["README.md", "README.MD", "readme.md", "Readme.md"]
            let branches = ["main", "master"]

            for branch in branches {
                for readmeName in readmeNames {
                    do {
                        let urlString = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(readmeName)"
                        guard let url = URL(string: urlString) else {
                            continue
                        }

                        let (data, response) = try await URLSession.shared.data(from: url)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            continue
                        }

                        if httpResponse.statusCode == 200,
                           let content = String(data: data, encoding: .utf8) {
                            return content
                        }
                    } catch {
                        // Try next variant/branch
                        continue
                    }
                }
            }

            throw PackageDownloadError.readmeNotFound
        }

        // MARK: - Documentation Site Detection

        /// Detect if package has hosted documentation
        public func detectDocumentationSite(
            owner: String,
            repo: String
        ) async -> DocumentationSite? {
            // Justification: KnownSite is a private helper struct that only exists to replace
            // a 4-member tuple (which would violate large_tuple rule). This struct is used
            // exclusively within this method to store known documentation site mappings.
            // Moving it outside would expose it unnecessarily and reduce code locality.
            // Trade-off: Accept nesting violation to avoid large_tuple violation and maintain encapsulation.
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

            // Check known sites first
            for site in knownSites {
                let knownOwner = site.owner
                let knownRepo = site.repo
                let urlString = site.url
                let type = site.type
                if owner.lowercased() == knownOwner.lowercased(),
                   repo.lowercased() == knownRepo.lowercased(),
                   let url = URL(string: urlString) {
                    return DocumentationSite(type: type, baseURL: url)
                }
            }

            // Try GitHub Pages convention: owner.github.io/repo
            if let githubPagesURL = URL(string: "https://\(owner).github.io/\(repo)/") {
                if await urlExists(githubPagesURL) {
                    return DocumentationSite(type: .githubPages, baseURL: githubPagesURL)
                }
            }

            return nil
        }

        // MARK: - File System Operations

        private func saveREADME(
            _ content: String,
            owner: String,
            repo: String
        ) async throws {
            let packageDir = outputDirectory
                .appendingPathComponent(owner)
                .appendingPathComponent(repo)

            // Create directory structure
            try FileManager.default.createDirectory(
                at: packageDir,
                withIntermediateDirectories: true
            )

            // Save README
            let readmePath = packageDir.appendingPathComponent("README.md")
            try content.write(to: readmePath, atomically: true, encoding: .utf8)
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
            // GitHub usernames and repo names can only contain:
            // alphanumeric, hyphens, and underscores
            // No path traversal attempts
            let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            return identifier.rangeOfCharacter(from: allowedCharacters.inverted) == nil
                && !identifier.isEmpty
                && !identifier.contains("..")
                && !identifier.hasPrefix("/")
        }

        // MARK: - Rate Limiting

        /// Apply priority-based rate limiting between package downloads
        private func applyRateLimit(for package: PackageReference, at index: Int) async throws {
            // Use higher delay for periodic checkpoints (every N packages)
            if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                try await Task.sleep(for: Shared.Constants.Delay.packageFetchHighPriority)
            } else {
                // Normal delay between downloads
                try await Task.sleep(for: Shared.Constants.Delay.packageFetchNormal)
            }
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            Log.info(message, category: .packages)
        }

        private func logError(_ message: String) {
            Log.error(message, category: .packages)
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
            return "Ensure the repository has a README.md file in the root directory"
        case .invalidInput:
            return "Provide a valid GitHub owner and repository name"
        case .networkError:
            return "Check your internet connection and try again"
        case .fileSystemError:
            return "Ensure you have write permissions to the output directory"
        }
    }
}
