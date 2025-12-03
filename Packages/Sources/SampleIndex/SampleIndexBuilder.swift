import Foundation
import OSLog

// MARK: - Sample Index Builder

// swiftlint:disable type_body_length function_body_length
// Justification: This actor manages complete ZIP extraction and indexing workflow.
// Breaking into smaller types would fragment the cohesive indexing logic.

extension SampleIndex {
    /// Builds the sample index by extracting ZIP files and indexing their contents
    public actor Builder {
        private let database: Database
        private let sampleCodeDirectory: URL
        private let logger = os.Logger(subsystem: "com.cupertino", category: "SampleIndex")

        /// Progress callback for indexing operations
        public typealias ProgressCallback = @Sendable (IndexProgress) -> Void

        public init(
            database: Database,
            sampleCodeDirectory: URL = SampleIndex.defaultSampleCodeDirectory
        ) {
            self.database = database
            self.sampleCodeDirectory = sampleCodeDirectory
        }

        // MARK: - Index Progress

        /// Progress information during indexing
        public struct IndexProgress: Sendable {
            public let currentProject: String
            public let projectIndex: Int
            public let totalProjects: Int
            public let filesIndexed: Int
            public let status: Status

            public enum Status: Sendable {
                case extracting
                case indexingFiles
                case completed
                case failed(String)
            }

            public var percentComplete: Double {
                guard totalProjects > 0 else { return 0 }
                return Double(projectIndex) / Double(totalProjects) * 100
            }
        }

        // MARK: - Index All Projects

        /// Index all sample code projects from the sample-code directory
        /// - Parameters:
        ///   - entries: Sample code entries with metadata (from SampleCodeCatalog)
        ///   - forceReindex: If true, reindex even if project already exists
        ///   - progress: Optional progress callback
        /// - Returns: Number of projects indexed
        public func indexAll(
            entries: [SampleCodeEntryInfo],
            forceReindex: Bool = false,
            progress: ProgressCallback? = nil
        ) async throws -> Int {
            // Find both ZIP files and extracted directories
            let zipFiles = try findZipFiles()
            let projectDirectories = try findProjectDirectories()

            logger.info("Found \(zipFiles.count) ZIP files in sample-code directory")
            logger.info("Found \(projectDirectories.count) extracted project directories")

            // Create lookup by zipFilename
            let entryLookup = Dictionary(
                entries.map { ($0.zipFilename, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            // Also create lookup by directory name (for extracted projects)
            let entryLookupByDir = Dictionary(
                entries.map { ($0.zipFilename.replacingOccurrences(of: ".zip", with: ""), $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var indexedCount = 0
            let totalProjects = zipFiles.count + projectDirectories.count

            // Index ZIP files
            for (index, zipURL) in zipFiles.enumerated() {
                let zipFilename = zipURL.lastPathComponent
                let projectId = projectIdFromZip(zipFilename)

                // Check if already indexed
                if !forceReindex {
                    if let existing = try await database.getProject(id: projectId) {
                        logger.debug("Skipping already indexed project: \(existing.title)")
                        continue
                    }
                }

                // Get metadata from catalog entry
                let entry = entryLookup[zipFilename]

                let progressInfo = IndexProgress(
                    currentProject: entry?.title ?? projectId,
                    projectIndex: index + 1,
                    totalProjects: totalProjects,
                    filesIndexed: 0,
                    status: .extracting
                )
                progress?(progressInfo)

                do {
                    let filesIndexed = try await indexProject(
                        zipURL: zipURL,
                        entry: entry,
                        forceReindex: forceReindex
                    )

                    let completedProgress = IndexProgress(
                        currentProject: entry?.title ?? projectId,
                        projectIndex: index + 1,
                        totalProjects: totalProjects,
                        filesIndexed: filesIndexed,
                        status: .completed
                    )
                    progress?(completedProgress)

                    indexedCount += 1
                    logger.info("Indexed project: \(entry?.title ?? projectId) (\(filesIndexed) files)")

                } catch {
                    let failedProgress = IndexProgress(
                        currentProject: entry?.title ?? projectId,
                        projectIndex: index + 1,
                        totalProjects: totalProjects,
                        filesIndexed: 0,
                        status: .failed(error.localizedDescription)
                    )
                    progress?(failedProgress)
                    logger.error("Failed to index \(zipFilename): \(error)")
                }
            }

            // Index extracted directories
            for (index, dirURL) in projectDirectories.enumerated() {
                let projectId = dirURL.lastPathComponent

                // Check if already indexed
                if !forceReindex {
                    if let existing = try await database.getProject(id: projectId) {
                        logger.debug("Skipping already indexed project: \(existing.title)")
                        continue
                    }
                }

                // Get metadata from catalog entry
                let entry = entryLookupByDir[projectId]

                let progressInfo = IndexProgress(
                    currentProject: entry?.title ?? projectId,
                    projectIndex: zipFiles.count + index + 1,
                    totalProjects: totalProjects,
                    filesIndexed: 0,
                    status: .indexingFiles
                )
                progress?(progressInfo)

                do {
                    let filesIndexed = try await indexProjectDirectory(
                        directoryURL: dirURL,
                        entry: entry,
                        forceReindex: forceReindex
                    )

                    let completedProgress = IndexProgress(
                        currentProject: entry?.title ?? projectId,
                        projectIndex: zipFiles.count + index + 1,
                        totalProjects: totalProjects,
                        filesIndexed: filesIndexed,
                        status: .completed
                    )
                    progress?(completedProgress)

                    indexedCount += 1
                    logger.info("Indexed project: \(entry?.title ?? projectId) (\(filesIndexed) files)")

                } catch {
                    let failedProgress = IndexProgress(
                        currentProject: entry?.title ?? projectId,
                        projectIndex: zipFiles.count + index + 1,
                        totalProjects: totalProjects,
                        filesIndexed: 0,
                        status: .failed(error.localizedDescription)
                    )
                    progress?(failedProgress)
                    logger.error("Failed to index directory \(projectId): \(error)")
                }
            }

            return indexedCount
        }

        // MARK: - Index Single Project

        /// Index a single project from a ZIP file
        /// - Parameters:
        ///   - zipURL: URL to the ZIP file
        ///   - entry: Optional metadata from SampleCodeCatalog
        ///   - forceReindex: If true, delete existing and reindex
        /// - Returns: Number of files indexed
        public func indexProject(
            zipURL: URL,
            entry: SampleCodeEntryInfo?,
            forceReindex: Bool = false
        ) async throws -> Int {
            let zipFilename = zipURL.lastPathComponent
            let projectId = projectIdFromZip(zipFilename)

            // Delete existing if force reindex
            if forceReindex {
                try await database.deleteProject(id: projectId)
            }

            // Extract ZIP to temp directory
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("sample-index-\(UUID().uuidString)")

            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            try extractZip(at: zipURL, to: tempDir)

            // Find the root project directory (usually one level down)
            let projectRoot = try findProjectRoot(in: tempDir)

            // Read README if exists
            let readme = readReadme(in: projectRoot)

            // Find all indexable files
            let files = try findIndexableFiles(in: projectRoot, projectId: projectId)

            // Calculate totals
            let totalSize = files.reduce(0) { $0 + $1.size }

            // Create project record
            let project = Project(
                id: projectId,
                title: entry?.title ?? titleFromProjectId(projectId),
                description: entry?.description ?? "",
                frameworks: entry?.frameworks ?? [],
                readme: readme,
                webURL: entry?.webURL ?? "",
                zipFilename: zipFilename,
                fileCount: files.count,
                totalSize: totalSize
            )

            // Index project
            try await database.indexProject(project)

            // Index all files
            for file in files {
                try await database.indexFile(file)
            }

            return files.count
        }

        // MARK: - Extract Project

        /// Extract a project ZIP to a destination directory
        /// - Parameters:
        ///   - projectId: Project ID (derived from ZIP filename)
        ///   - destination: Where to extract the project
        /// - Returns: URL to the extracted project root
        public func extractProject(projectId: String, to destination: URL) async throws -> URL {
            let zipFilename = "\(projectId).zip"
            let zipURL = sampleCodeDirectory.appendingPathComponent(zipFilename)

            guard FileManager.default.fileExists(atPath: zipURL.path) else {
                throw Error.fileNotFound(zipFilename)
            }

            try extractZip(at: zipURL, to: destination)
            return try findProjectRoot(in: destination)
        }

        // MARK: - Private Helpers

        /// Find all ZIP files in the sample code directory
        private func findZipFiles() throws -> [URL] {
            guard FileManager.default.fileExists(atPath: sampleCodeDirectory.path) else {
                return []
            }

            let contents = try FileManager.default.contentsOfDirectory(
                at: sampleCodeDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return contents
                .filter { $0.pathExtension.lowercased() == "zip" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        /// Find all extracted project directories in the sample code directory
        /// This includes projects from GitHub clone (cupertino-sample-code subdirectory)
        private func findProjectDirectories() throws -> [URL] {
            guard FileManager.default.fileExists(atPath: sampleCodeDirectory.path) else {
                return []
            }

            var projectDirs: [URL] = []

            // Check for GitHub-cloned repo directory
            let gitHubRepoDir = sampleCodeDirectory.appendingPathComponent("cupertino-sample-code")
            if FileManager.default.fileExists(atPath: gitHubRepoDir.path) {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: gitHubRepoDir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )

                for item in contents {
                    guard isValidProjectDirectory(item) else { continue }
                    projectDirs.append(item)
                }
            }

            // Also check top-level directories (for manually extracted projects)
            let topLevelContents = try FileManager.default.contentsOfDirectory(
                at: sampleCodeDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for item in topLevelContents {
                // Skip the GitHub repo directory itself (we already scanned inside it)
                guard item.lastPathComponent != "cupertino-sample-code" else { continue }
                guard isValidProjectDirectory(item) else { continue }
                projectDirs.append(item)
            }

            return projectDirs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        /// Check if a directory is a valid Xcode/Swift project
        private func isValidProjectDirectory(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return false
            }

            // Check for Xcode project indicators
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                return false
            }

            let hasXcodeproj = contents.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
            let hasPackageSwift = contents.contains { $0 == "Package.swift" }
            let hasSwiftFiles = contents.contains { $0.hasSuffix(".swift") }

            return hasXcodeproj || hasPackageSwift || hasSwiftFiles
        }

        /// Index a single project from an extracted directory
        /// - Parameters:
        ///   - directoryURL: URL to the project directory
        ///   - entry: Optional metadata from SampleCodeCatalog
        ///   - forceReindex: If true, delete existing and reindex
        /// - Returns: Number of files indexed
        public func indexProjectDirectory(
            directoryURL: URL,
            entry: SampleCodeEntryInfo?,
            forceReindex: Bool = false
        ) async throws -> Int {
            let projectId = directoryURL.lastPathComponent

            // Delete existing if force reindex
            if forceReindex {
                try await database.deleteProject(id: projectId)
            }

            // Use directory directly (no extraction needed)
            let projectRoot = directoryURL

            // Read README if exists
            let readme = readReadme(in: projectRoot)

            // Find all indexable files
            let files = try findIndexableFiles(in: projectRoot, projectId: projectId)

            // Calculate totals
            let totalSize = files.reduce(0) { $0 + $1.size }

            // Create project record
            let project = Project(
                id: projectId,
                title: entry?.title ?? titleFromProjectId(projectId),
                description: entry?.description ?? "",
                frameworks: entry?.frameworks ?? [],
                readme: readme,
                webURL: entry?.webURL ?? "",
                zipFilename: "", // No ZIP file for extracted directories
                fileCount: files.count,
                totalSize: totalSize
            )

            // Index project
            try await database.indexProject(project)

            // Index all files
            for file in files {
                try await database.indexFile(file)
            }

            return files.count
        }

        /// Extract project ID from ZIP filename
        private func projectIdFromZip(_ filename: String) -> String {
            // Remove .zip extension
            var id = filename
            if id.lowercased().hasSuffix(".zip") {
                id = String(id.dropLast(4))
            }
            return id
        }

        /// Generate title from project ID
        private func titleFromProjectId(_ projectId: String) -> String {
            // Convert kebab-case to Title Case
            projectId
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }

        /// Extract ZIP file to destination
        private func extractZip(at zipURL: URL, to destination: URL) throws {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", "-o", zipURL.path, "-d", destination.path]

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw Error.zipExtractionFailed(errorMessage)
            }
        }

        /// Find the actual project root directory (may be nested)
        private func findProjectRoot(in directory: URL) throws -> URL {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            // If there's exactly one directory and no files, go into it
            let directories = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            let files = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            }

            if directories.count == 1, files.isEmpty {
                return directories[0]
            }

            return directory
        }

        /// Read README.md from project root
        private func readReadme(in projectRoot: URL) -> String? {
            let readmeNames = ["README.md", "Readme.md", "readme.md", "README.txt", "README"]

            for name in readmeNames {
                let readmeURL = projectRoot.appendingPathComponent(name)
                if let content = try? String(contentsOf: readmeURL, encoding: .utf8) {
                    return content
                }
            }

            return nil
        }

        /// Find all indexable source files in the project
        private func findIndexableFiles(in projectRoot: URL, projectId: String) throws -> [File] {
            var files: [File] = []

            let enumerator = FileManager.default.enumerator(
                at: projectRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                // Skip directories
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    continue
                }

                // Get relative path
                let relativePath = fileURL.path.replacingOccurrences(
                    of: projectRoot.path + "/",
                    with: ""
                )

                // Skip non-indexable files
                guard SampleIndex.shouldIndex(path: relativePath) else {
                    continue
                }

                // Skip very large files (> 1MB)
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard fileSize < 1000000 else {
                    logger.debug("Skipping large file: \(relativePath) (\(fileSize) bytes)")
                    continue
                }

                // Read content
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    logger.debug("Skipping non-UTF8 file: \(relativePath)")
                    continue
                }

                let file = File(
                    projectId: projectId,
                    path: relativePath,
                    content: content
                )
                files.append(file)
            }

            return files
        }
    }

    // MARK: - Sample Code Entry Info

    /// Minimal info needed from SampleCodeCatalog for indexing
    public struct SampleCodeEntryInfo: Sendable {
        public let title: String
        public let description: String
        public let frameworks: [String]
        public let webURL: String
        public let zipFilename: String

        public init(
            title: String,
            description: String,
            frameworks: [String],
            webURL: String,
            zipFilename: String
        ) {
            self.title = title
            self.description = description
            self.frameworks = frameworks
            self.webURL = webURL
            self.zipFilename = zipFilename
        }
    }
}

// swiftlint:enable type_body_length function_body_length
