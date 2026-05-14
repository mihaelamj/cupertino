import Foundation
import SharedConstants
import SharedUtils

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Availability Fetcher

// swiftlint:disable type_body_length
// Justification: Availability.Fetcher is a self-contained actor that handles availability data fetching.
// It manages API calls, caching, fallback strategies, and statistics tracking as a cohesive unit.
// Splitting would fragment the actor's state management and reduce thread-safety guarantees.

/// Fetches platform availability data from Apple's API and updates existing documentation JSONs
extension Availability {
    public actor Fetcher {
        // MARK: - Configuration

        /// Configuration for the availability fetcher
        public struct Configuration: Sendable {
            /// Maximum concurrent requests
            public let concurrency: Int

            /// Request timeout in seconds
            public let timeout: TimeInterval

            /// Whether to skip documents that already have availability
            public let skipExisting: Bool

            /// Base URL for Apple's tutorials/data API
            public let apiBaseURL: String

            public init(
                concurrency: Int = 50,
                timeout: TimeInterval = 1.0,
                skipExisting: Bool = false,
                apiBaseURL: String = Shared.Constants.BaseURL.appleTutorialsDocs
            ) {
                self.concurrency = concurrency
                self.timeout = timeout
                self.skipExisting = skipExisting
                self.apiBaseURL = apiBaseURL
            }

            /// Default configuration
            public static let `default` = Configuration()

            /// Fast configuration for quick updates
            public static let fast = Configuration(
                concurrency: 100,
                timeout: 0.5,
                skipExisting: true
            )
        }

        // MARK: - Properties

        private let docsDirectory: URL
        private let configuration: Configuration
        private let urlSession: URLSession

        /// Cache of framework-level availability for inheritance
        private var frameworkAvailabilityCache: [String: [Availability.Platform]] = [:]

        /// Cache of all document availability (populated in pass 1, used in pass 2 for articles)
        private var documentAvailabilityCache: [String: [Availability.Platform]] = [:]

        // MARK: - Initialization

        public init(
            docsDirectory: URL,
            configuration: Configuration = .default
        ) {
            self.docsDirectory = docsDirectory
            self.configuration = configuration

            // Configure URLSession with timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = configuration.timeout
            config.timeoutIntervalForResource = configuration.timeout * 2
            config.httpMaximumConnectionsPerHost = configuration.concurrency
            urlSession = URLSession(configuration: config)
        }

        // MARK: - Public API

        /// Fetch availability data and update all documentation JSONs
        public func fetch(
            onProgress: (@Sendable (Availability.Progress) -> Void)? = nil
        ) async throws -> Availability.Statistics {
            var stats = Availability.Statistics(startTime: Date())

            // Discover all frameworks
            let frameworks = try discoverFrameworks()
            guard !frameworks.isEmpty else {
                throw Availability.Error.noDocumentationFound
            }

            // Collect all JSON files
            let allFiles = try collectJSONFiles(from: frameworks)
            stats.totalDocuments = allFiles.count
            stats.frameworksProcessed = frameworks.count

            // Process files with concurrency
            try await processFiles(
                allFiles,
                stats: &stats,
                onProgress: onProgress
            )

            stats.endTime = Date()
            return stats
        }

        // MARK: - Private Methods - Discovery

        private func discoverFrameworks() throws -> [String] {
            let contents = try FileManager.default.contentsOfDirectory(
                at: docsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            return contents.compactMap { url -> String? in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
                return isDirectory == true ? url.lastPathComponent : nil
            }.sorted()
        }

        private func collectJSONFiles(from frameworks: [String]) throws -> [(framework: String, file: URL)] {
            var files: [(String, URL)] = []

            for framework in frameworks {
                let frameworkDir = docsDirectory.appendingPathComponent(framework)
                let contents = try FileManager.default.contentsOfDirectory(
                    at: frameworkDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )

                for file in contents where file.pathExtension == "json" {
                    files.append((framework, file))
                }
            }

            return files
        }

        // MARK: - Private Methods - Processing

        private func processFiles(
            _ files: [(framework: String, file: URL)],
            stats: inout Availability.Statistics,
            onProgress: (@Sendable (Availability.Progress) -> Void)?
        ) async throws {
            // Phase 1: Cache framework root availability
            await cacheFrameworkAvailability(from: files)

            // Phase 2: First pass - process API docs (non-articles) and cache their availability
            // This populates documentAvailabilityCache for article reference lookups
            let (apiDocs, articles) = separateAPIDocsAndArticles(files)

            let batchSize = configuration.concurrency
            var completed = 0
            var successful = 0
            var failed = 0
            var filesWithNoAvailability: [String] = []

            // Process API docs first
            for batch in stride(from: 0, to: apiDocs.count, by: batchSize) {
                let endIndex = min(batch + batchSize, apiDocs.count)
                let batchFiles = Array(apiDocs[batch..<endIndex])

                await withTaskGroup(of: ProcessResult.self) { group in
                    for (framework, file) in batchFiles {
                        group.addTask {
                            await self.processFile(file, framework: framework, isArticle: false)
                        }
                    }

                    for await result in group {
                        completed += 1
                        updateStats(
                            result: result,
                            stats: &stats,
                            successful: &successful,
                            failed: &failed,
                            filesWithNoAvailability: &filesWithNoAvailability
                        )

                        reportProgress(
                            result: result,
                            completed: completed,
                            total: files.count,
                            successful: successful,
                            failed: failed,
                            onProgress: onProgress
                        )
                    }
                }
            }

            // Phase 3: Second pass - process articles with reference lookup
            for batch in stride(from: 0, to: articles.count, by: batchSize) {
                let endIndex = min(batch + batchSize, articles.count)
                let batchFiles = Array(articles[batch..<endIndex])

                await withTaskGroup(of: ProcessResult.self) { group in
                    for (framework, file) in batchFiles {
                        group.addTask {
                            await self.processFile(file, framework: framework, isArticle: true)
                        }
                    }

                    for await result in group {
                        completed += 1
                        updateStats(
                            result: result,
                            stats: &stats,
                            successful: &successful,
                            failed: &failed,
                            filesWithNoAvailability: &filesWithNoAvailability
                        )

                        reportProgress(
                            result: result,
                            completed: completed,
                            total: files.count,
                            successful: successful,
                            failed: failed,
                            onProgress: onProgress
                        )
                    }
                }
            }

            // Store files with no availability for logging (limit to first 100)
            stats.filesWithNoAvailability = Array(filesWithNoAvailability.prefix(100))
        }

        /// Separate files into API docs and articles based on document kind
        private func separateAPIDocsAndArticles(
            _ files: [(framework: String, file: URL)]
        ) -> (apiDocs: [(framework: String, file: URL)], articles: [(framework: String, file: URL)]) {
            var apiDocs: [(String, URL)] = []
            var articles: [(String, URL)] = []

            for (framework, file) in files {
                if let data = try? Data(contentsOf: file),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let kind = json["kind"] as? String,
                   kind == "article" {
                    articles.append((framework, file))
                } else {
                    apiDocs.append((framework, file))
                }
            }

            return (apiDocs, articles)
        }

        private func updateStats(
            result: ProcessResult,
            stats: inout Availability.Statistics,
            successful: inout Int,
            failed: inout Int,
            filesWithNoAvailability: inout [String]
        ) {
            switch result.status {
            case .updated:
                stats.updatedDocuments += 1
                stats.successfulFetches += 1
                successful += 1
            case .inherited:
                stats.inheritedFromParent += 1
                stats.updatedDocuments += 1
                successful += 1
            case .derivedFromReferences:
                stats.derivedFromReferences += 1
                stats.updatedDocuments += 1
                successful += 1
            case .markedEmpty:
                stats.markedEmpty += 1
                filesWithNoAvailability.append("\(result.framework)/\(result.filename)")
            case .skipped:
                stats.skippedDocuments += 1
            case .failed:
                stats.failedFetches += 1
                failed += 1
            case .notApplicable:
                stats.skippedDocuments += 1
            }
        }

        private func reportProgress(
            result: ProcessResult,
            completed: Int,
            total: Int,
            successful: Int,
            failed: Int,
            onProgress: (@Sendable (Availability.Progress) -> Void)?
        ) {
            if let onProgress {
                let progress = Availability.Progress(
                    currentDocument: result.filename,
                    completed: completed,
                    total: total,
                    successful: successful,
                    failed: failed,
                    currentFramework: result.framework
                )
                onProgress(progress)
            }
        }

        /// Cache framework-level availability by processing root documentation files
        private func cacheFrameworkAvailability(from files: [(framework: String, file: URL)]) async {
            // Find framework root files (e.g., documentation_swiftui.json)
            let frameworkRoots = files.filter { framework, file in
                let filename = file.deletingPathExtension().lastPathComponent
                return filename == "documentation_\(framework)"
            }

            // Process framework roots to cache their availability
            for (framework, file) in frameworkRoots {
                if let data = try? Data(contentsOf: file),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let availabilityArray = json["availability"] as? [[String: Any]] {
                    let platforms = availabilityArray.compactMap { dict -> Availability.Platform? in
                        guard let name = dict["name"] as? String else { return nil }
                        return Availability.Platform(
                            name: name,
                            introducedAt: dict["introducedAt"] as? String,
                            deprecated: dict["deprecated"] as? Bool ?? false,
                            deprecatedAt: dict["deprecatedAt"] as? String,
                            unavailable: dict["unavailable"] as? Bool ?? false,
                            beta: dict["beta"] as? Bool ?? false
                        )
                    }
                    if !platforms.isEmpty {
                        frameworkAvailabilityCache[framework] = platforms
                    }
                }
            }
        }

        private func processFile(
            _ fileURL: URL,
            framework: String,
            isArticle: Bool
        ) async -> ProcessResult {
            let filename = fileURL.lastPathComponent

            // Load existing JSON
            guard let data = try? Data(contentsOf: fileURL),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ProcessResult(status: .failed, filename: filename, framework: framework)
            }

            // Check if already has availability (if skipExisting is enabled)
            if configuration.skipExisting,
               let existingAvailability = json["availability"] as? [[String: Any]],
               !existingAvailability.isEmpty {
                return ProcessResult(status: .skipped, filename: filename, framework: framework)
            }

            // Extract URL to build API path
            guard let urlString = json["url"] as? String,
                  let docURL = URL(string: urlString)
            else {
                return ProcessResult(status: .notApplicable, filename: filename, framework: framework)
            }

            // Build API URL from doc URL
            // https://developer.apple.com/documentation/SwiftUI/View
            // -> https://developer.apple.com/tutorials/data/documentation/swiftui/view.json
            let apiURL = buildAPIURL(from: docURL)

            // Fetch availability from API
            var availability: Availability.Info? = await fetchAvailability(from: apiURL)
            var inherited = false
            var derivedFromRefs = false

            // Fallback 1: If API failed or returned empty, try parsing @available from local content
            if availability?.isEmpty ?? true {
                availability = Availability.Info.extractFromJSONContent(data)
            }

            // Fallback 2: For articles, derive from referenced APIs
            if isArticle, availability?.isEmpty ?? true {
                if let derived = deriveAvailabilityFromReferences(json: json) {
                    availability = derived
                    derivedFromRefs = true
                }
            }

            // Fallback 3: If still no availability, try inheriting from framework
            if availability?.isEmpty ?? true,
               let frameworkPlatforms = frameworkAvailabilityCache[framework] {
                availability = Availability.Info(platforms: frameworkPlatforms)
                inherited = true
            }

            // Determine the final status and what to write
            let finalStatus: ProcessResult.Status
            let platformsToWrite: [[String: Any]]

            if let availability, !availability.isEmpty {
                // We have availability data
                platformsToWrite = availability.platforms.map { platform in
                    var dict: [String: Any] = [
                        "name": platform.name,
                        "deprecated": platform.deprecated,
                        "unavailable": platform.unavailable,
                        "beta": platform.beta,
                    ]
                    if let introduced = platform.introducedAt {
                        dict["introducedAt"] = introduced
                    }
                    if let deprecatedAt = platform.deprecatedAt {
                        dict["deprecatedAt"] = deprecatedAt
                    }
                    return dict
                }
                if derivedFromRefs {
                    finalStatus = .derivedFromReferences
                } else if inherited {
                    finalStatus = .inherited
                } else {
                    finalStatus = .updated
                }

                // Cache availability for this document (for article reference lookups)
                let cacheKey = docURL.path.lowercased()
                cacheDocumentAvailability(key: cacheKey, platforms: availability.platforms)
            } else {
                // Fallback 4: Mark with empty availability to indicate we checked
                platformsToWrite = []
                finalStatus = .markedEmpty
            }

            // Update JSON with availability (even if empty)
            json["availability"] = platformsToWrite

            // Write updated JSON
            do {
                let updatedData = try JSONSerialization.data(
                    withJSONObject: json,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try updatedData.write(to: fileURL)
                return ProcessResult(status: finalStatus, filename: filename, framework: framework)
            } catch {
                return ProcessResult(status: .failed, filename: filename, framework: framework)
            }
        }

        /// Cache document availability for reference lookups
        private func cacheDocumentAvailability(key: String, platforms: [Availability.Platform]) {
            documentAvailabilityCache[key] = platforms
        }

        /// Derive availability from doc:// references in article content
        private func deriveAvailabilityFromReferences(json: [String: Any]) -> Availability.Info? {
            guard let rawMarkdown = json["rawMarkdown"] as? String else { return nil }

            // Extract doc:// references from markdown
            // Pattern: [doc://com.apple.storekit/documentation/StoreKit/Transaction]
            // or: [doc://com.apple.documentation/documentation/Foundation/URL]
            let docRefPattern = #"doc://[^/]+/documentation/([^\]]+)"#
            guard let regex = try? NSRegularExpression(pattern: docRefPattern, options: []) else {
                return nil
            }

            let range = NSRange(rawMarkdown.startIndex..., in: rawMarkdown)
            let matches = regex.matches(in: rawMarkdown, options: [], range: range)

            var allPlatforms: [[Availability.Platform]] = []

            for match in matches {
                guard let pathRange = Range(match.range(at: 1), in: rawMarkdown) else { continue }
                let refPath = String(rawMarkdown[pathRange]).lowercased()

                // Build the full path for cache lookup
                let cacheKey = "/documentation/\(refPath)"

                if let platforms = documentAvailabilityCache[cacheKey], !platforms.isEmpty {
                    allPlatforms.append(platforms)
                }
            }

            guard !allPlatforms.isEmpty else { return nil }

            // Compute most restrictive availability (highest minimum version per platform)
            return computeMostRestrictiveAvailability(from: allPlatforms)
        }

        /// Compute the most restrictive availability from multiple sources
        /// Uses the highest minimum version for each platform
        private func computeMostRestrictiveAvailability(
            from sources: [[Availability.Platform]]
        ) -> Availability.Info? {
            var platformVersions: [String: (version: String, deprecated: Bool, beta: Bool)] = [:]

            for platforms in sources {
                for platform in platforms where !platform.unavailable {
                    guard let version = platform.introducedAt else { continue }

                    if let existing = platformVersions[platform.name] {
                        // Keep the higher (more restrictive) version
                        if Self.isVersion(version, greaterThan: existing.version) {
                            platformVersions[platform.name] = (
                                version,
                                platform.deprecated || existing.deprecated,
                                platform.beta || existing.beta
                            )
                        }
                    } else {
                        platformVersions[platform.name] = (version, platform.deprecated, platform.beta)
                    }
                }
            }

            guard !platformVersions.isEmpty else { return nil }

            let platforms = platformVersions.map { name, info in
                Availability.Platform(
                    name: name,
                    introducedAt: info.version,
                    deprecated: info.deprecated,
                    deprecatedAt: nil,
                    unavailable: false,
                    beta: info.beta
                )
            }

            return Availability.Info(platforms: platforms)
        }

        /// Compare version strings - returns true if lhs > rhs
        private static func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
            let lhsComponents = lhs.split(separator: ".").compactMap { Int($0) }
            let rhsComponents = rhs.split(separator: ".").compactMap { Int($0) }

            for idx in 0..<max(lhsComponents.count, rhsComponents.count) {
                let lhsValue = idx < lhsComponents.count ? lhsComponents[idx] : 0
                let rhsValue = idx < rhsComponents.count ? rhsComponents[idx] : 0

                if lhsValue > rhsValue { return true }
                if lhsValue < rhsValue { return false }
            }
            return false // Equal versions
        }

        func buildAPIURL(from docURL: URL) -> URL {
            // Extract path after /documentation/
            let path = docURL.path.lowercased()
            let apiPath: String

            if path.hasPrefix("/documentation/") {
                apiPath = String(path.dropFirst("/documentation/".count))
            } else {
                apiPath = path
            }

            return try! URL(knownGood: "\(configuration.apiBaseURL)/\(apiPath).json")
        }

        private func fetchAvailability(from url: URL) async -> Availability.Info? {
            do {
                let (data, response) = try await urlSession.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    return nil
                }

                guard httpResponse.statusCode == 200 else {
                    return nil
                }

                let decoder = JSONDecoder()
                let apiResponse = try decoder.decode(Availability.APIResponse.self, from: data)

                guard let platforms = apiResponse.metadata?.platforms else {
                    return nil
                }

                let availability = platforms.map { $0.toPlatform() }
                return Availability.Info(platforms: availability)
            } catch {
                // Network error or JSON parse error - return nil to mark as failed
                return nil
            }
        }
    }

    // MARK: - Process Result

    private struct ProcessResult {
        enum Status {
            case updated // Availability fetched from API or parsed from @available
            case inherited // Inherited from parent/framework
            case derivedFromReferences // Derived from doc:// references (articles)
            case markedEmpty // Checked but no availability found, marked with empty array
            case skipped // Already has availability (when skipExisting is true)
            case failed // JSON parsing or write error
            case notApplicable // No URL to fetch from
        }

        let status: Status
        let filename: String
        let framework: String
    }
}
