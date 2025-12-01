import Foundation
import Logging
import Shared

// MARK: - Sample Code Cleaner

/// Actor for cleaning sample code archives by removing unnecessary files
/// such as .git folders, .DS_Store, build artifacts, etc.
public actor SampleCodeCleaner {
    private let sampleCodeDirectory: URL
    private let dryRun: Bool
    private let keepOriginals: Bool

    /// Patterns of files/folders to remove from archives
    private static let cleanupPatterns: [String] = [
        ".git",
        ".gitignore",
        ".gitattributes",
        ".DS_Store",
        ".Trashes",
        "._*",
        "xcuserdata",
        "*.xcuserstate",
        "DerivedData",
        "build",
        ".build",
        "Pods",
        ".swiftpm",
        "*.xcworkspace/xcuserdata",
        "*.xcodeproj/xcuserdata",
        "*.xcodeproj/project.xcworkspace/xcuserdata",
        "__MACOSX",
    ]

    public init(
        sampleCodeDirectory: URL = Shared.Constants.defaultSampleCodeDirectory,
        dryRun: Bool = false,
        keepOriginals: Bool = false
    ) {
        self.sampleCodeDirectory = sampleCodeDirectory
        self.dryRun = dryRun
        self.keepOriginals = keepOriginals
    }

    // MARK: - Public Methods

    /// Clean all ZIP archives in the sample code directory
    public func cleanup(
        onProgress: (@Sendable (CleanupProgress) -> Void)? = nil
    ) async throws -> CleanupStatistics {
        let startTime = Date()

        // Find all ZIP files
        let zipFiles = try findZipFiles()

        guard !zipFiles.isEmpty else {
            Log.info("No ZIP files found in \(sampleCodeDirectory.path)", category: .samples)
            return CleanupStatistics(
                totalArchives: 0,
                cleanedArchives: 0,
                skippedArchives: 0,
                errors: 0,
                originalTotalSize: 0,
                cleanedTotalSize: 0,
                duration: Date().timeIntervalSince(startTime)
            )
        }

        Log.info("Found \(zipFiles.count) ZIP archives to process", category: .samples)

        var cleanedArchives = 0
        var skippedArchives = 0
        var errors = 0
        var originalTotalSize: Int64 = 0
        var cleanedTotalSize: Int64 = 0
        var totalItemsRemoved = 0

        for (index, zipFile) in zipFiles.enumerated() {
            let result = await cleanArchive(at: zipFile)

            originalTotalSize += result.originalSize
            cleanedTotalSize += result.cleanedSize
            totalItemsRemoved += result.itemsRemoved

            if result.success {
                if result.itemsRemoved > 0 {
                    cleanedArchives += 1
                } else {
                    skippedArchives += 1
                }
            } else {
                errors += 1
                if let error = result.errorMessage {
                    Log.error("Failed to clean \(zipFile.lastPathComponent): \(error)", category: .samples)
                }
            }

            onProgress?(CleanupProgress(
                current: index + 1,
                total: zipFiles.count,
                currentFile: zipFile.lastPathComponent,
                originalSize: originalTotalSize,
                cleanedSize: cleanedTotalSize
            ))
        }

        return CleanupStatistics(
            totalArchives: zipFiles.count,
            cleanedArchives: cleanedArchives,
            skippedArchives: skippedArchives,
            errors: errors,
            originalTotalSize: originalTotalSize,
            cleanedTotalSize: cleanedTotalSize,
            totalItemsRemoved: totalItemsRemoved,
            duration: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Private Methods

    /// Find all ZIP files in the sample code directory
    private func findZipFiles() throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: sampleCodeDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return contents.filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Clean a single archive
    private func cleanArchive(at zipURL: URL) async -> CleanupResult {
        let filename = zipURL.lastPathComponent

        // Get original size
        let originalSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
            originalSize = (attributes[.size] as? Int64) ?? 0
        } catch {
            return CleanupResult(
                filename: filename,
                originalSize: 0,
                cleanedSize: 0,
                itemsRemoved: 0,
                success: false,
                errorMessage: "Failed to get file size: \(error.localizedDescription)"
            )
        }

        // Dry run - just report what would be cleaned
        if dryRun {
            let itemsToRemove = await countItemsToRemove(in: zipURL)
            return CleanupResult(
                filename: filename,
                originalSize: originalSize,
                cleanedSize: originalSize,
                itemsRemoved: itemsToRemove,
                success: true
            )
        }

        // Create temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            // Create temp directory
            try FileManager.default.createDirectory(
                at: tempDir,
                withIntermediateDirectories: true
            )

            // Extract ZIP
            let extractResult = try await extractZip(zipURL, to: tempDir)
            guard extractResult else {
                return CleanupResult(
                    filename: filename,
                    originalSize: originalSize,
                    cleanedSize: originalSize,
                    itemsRemoved: 0,
                    success: false,
                    errorMessage: "Failed to extract archive"
                )
            }

            // Remove unwanted files/folders
            let itemsRemoved = try removeUnwantedItems(in: tempDir)

            // Skip recompression if nothing was removed
            if itemsRemoved == 0 {
                return CleanupResult(
                    filename: filename,
                    originalSize: originalSize,
                    cleanedSize: originalSize,
                    itemsRemoved: 0,
                    success: true
                )
            }

            // Recompress
            let cleanedZipURL: URL
            if keepOriginals {
                cleanedZipURL = zipURL.deletingPathExtension()
                    .appendingPathExtension("cleaned.zip")
            } else {
                cleanedZipURL = zipURL
            }

            // Remove original if replacing
            if !keepOriginals {
                try FileManager.default.removeItem(at: zipURL)
            }

            let compressResult = try await compressDirectory(tempDir, to: cleanedZipURL)
            guard compressResult else {
                return CleanupResult(
                    filename: filename,
                    originalSize: originalSize,
                    cleanedSize: originalSize,
                    itemsRemoved: itemsRemoved,
                    success: false,
                    errorMessage: "Failed to recompress archive"
                )
            }

            // Get new size
            let newAttributes = try FileManager.default.attributesOfItem(atPath: cleanedZipURL.path)
            let cleanedSize = (newAttributes[.size] as? Int64) ?? 0

            return CleanupResult(
                filename: filename,
                originalSize: originalSize,
                cleanedSize: cleanedSize,
                itemsRemoved: itemsRemoved,
                success: true
            )

        } catch {
            return CleanupResult(
                filename: filename,
                originalSize: originalSize,
                cleanedSize: originalSize,
                itemsRemoved: 0,
                success: false,
                errorMessage: error.localizedDescription
            )
        }
    }

    /// Extract ZIP archive using ditto (preserves permissions and attributes)
    private func extractZip(_ zipURL: URL, to destination: URL) async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, destination.path]

        try process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0
    }

    /// Compress directory to ZIP using ditto
    private func compressDirectory(_ directory: URL, to zipURL: URL) async throws -> Bool {
        // Get the contents of the temp directory (should be a single folder)
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        // Use the first directory as the source (this is the project folder)
        let sourceDir = contents.first ?? directory

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-ck", "--keepParent", sourceDir.path, zipURL.path]

        try process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0
    }

    /// Remove unwanted items from extracted directory
    private func removeUnwantedItems(in directory: URL) throws -> Int {
        var itemsRemoved = 0

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return 0
        }

        var itemsToRemove: [URL] = []

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent

            if shouldRemove(name: name, url: fileURL) {
                itemsToRemove.append(fileURL)

                // Skip enumeration inside directories we're removing
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    enumerator.skipDescendants()
                }
            }
        }

        // Sort by path length (longest first) to remove nested items before parents
        itemsToRemove.sort { $0.path.count > $1.path.count }

        for itemURL in itemsToRemove {
            do {
                try FileManager.default.removeItem(at: itemURL)
                itemsRemoved += 1
                Log.debug("Removed: \(itemURL.path)", category: .samples)
            } catch {
                Log.warning("Failed to remove \(itemURL.path): \(error)", category: .samples)
            }
        }

        return itemsRemoved
    }

    /// Check if a file/folder should be removed
    private func shouldRemove(name: String, url: URL) -> Bool {
        for pattern in Self.cleanupPatterns {
            if pattern.contains("*") {
                // Wildcard pattern
                let regex = pattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                if name.range(of: "^\(regex)$", options: .regularExpression) != nil {
                    return true
                }
            } else {
                // Exact match
                if name == pattern {
                    return true
                }
            }
        }
        return false
    }

    /// Count items that would be removed (for dry run)
    private func countItemsToRemove(in zipURL: URL) async -> Int {
        // For dry run, we use zipinfo to inspect without extracting
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zipURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return 0
            }

            let files = output.components(separatedBy: "\n")
            var count = 0

            for file in files where !file.isEmpty {
                if shouldRemovePath(file) {
                    count += 1
                }
            }

            return count
        } catch {
            return 0
        }
    }

    /// Check if a path should be removed (checks all path components)
    private func shouldRemovePath(_ path: String) -> Bool {
        let components = path.components(separatedBy: "/")
        for component in components {
            if shouldRemove(name: component, url: URL(fileURLWithPath: path)) {
                return true
            }
        }
        return false
    }
}
