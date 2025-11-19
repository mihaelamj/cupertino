import Core
import Foundation
import Resources
import Shared

@main
struct PackageCuratorApp {
    static func main() async throws {
        // Load packages
        let packages = await SwiftPackagesCatalog.allPackages
        let priorityURLs = await PriorityPackagesCatalog.allPackages.map(\.url)

        // Check which packages are downloaded
        let docsDirectory = Shared.Constants.defaultDocsDirectory
        let downloadedPackages = checkDownloadedPackages(in: docsDirectory)

        // Load configuration
        let config = ConfigManager.load()

        // Initialize state
        let state = AppState()
        state.baseDirectory = config.baseDirectory
        state.packages = packages.map { pkg in
            let isSelected = priorityURLs.contains(pkg.url)
            let isDownloaded = downloadedPackages.contains("\(pkg.owner)/\(pkg.repo)".lowercased())
            return PackageEntry(package: pkg, isSelected: isSelected, isDownloaded: isDownloaded)
        }

        // Scan library artifacts
        var artifacts = scanLibraryArtifacts()

        // Initialize UI components
        let screen = Screen()
        let input = Input()
        let homeView = HomeView()
        let packageView = PackageView()
        let libraryView = LibraryView()
        let settingsView = SettingsView()
        var homeCursor = 0
        var libraryCursor = 0
        var settingsCursor = 0

        // Setup terminal
        let originalTermios = await screen.enableRawMode()
        await screen.enterAltScreen()
        print(Screen.hideCursor, terminator: "")

        var running = true
        // Initialize with actual terminal size to avoid false initial "resize"
        var lastSize = await screen.getSize()

        while running {
            // Get current terminal size (handles resize)
            let (rows, cols) = await screen.getSize()

            // Detect resize
            let didResize = rows != lastSize.rows || cols != lastSize.cols
            if didResize {
                lastSize = (rows, cols)
                // Force a full redraw on next render
                print(Screen.clearScreen + Screen.home, terminator: "")
                fflush(stdout)
            }

            // Render current view using extracted helper
            let pageSize = rows - 4
            let content = renderCurrentView(
                state: state,
                rows: rows,
                cols: cols,
                pageSize: pageSize,
                homeCursor: homeCursor,
                libraryCursor: libraryCursor,
                settingsCursor: settingsCursor,
                artifacts: artifacts,
                homeView: homeView,
                packageView: packageView,
                libraryView: libraryView,
                settingsView: settingsView
            )
            await screen.render(content)

            // Handle input (non-blocking with 0.1s timeout in terminal)
            if let key = input.readKey() {
                // Check for view transitions
                if let newView = ViewRouter.handleViewTransition(key: key, state: state, homeCursor: homeCursor) {
                    state.viewMode = newView
                    continue
                }

                // Process input and update state
                let result = InputHandler.handleInput(
                    key,
                    state: state,
                    homeCursor: &homeCursor,
                    libraryCursor: &libraryCursor,
                    settingsCursor: &settingsCursor,
                    artifacts: artifacts,
                    pageSize: pageSize
                )

                switch result {
                case .quit:
                    running = false
                case .continueRunning:
                    continue
                case .render:
                    // Check if we need to reload artifacts after settings change
                    if state.statusMessage.contains("Reloading") {
                        // Force a render to show "Reloading..." message
                        let reloadContent = settingsView.render(
                            cursor: settingsCursor,
                            width: cols,
                            height: rows,
                            baseDirectory: state.baseDirectory,
                            isEditing: false,
                            editBuffer: "",
                            statusMessage: state.statusMessage
                        )
                        await screen.render(reloadContent)

                        // Reload artifacts and package status from new base directory
                        artifacts = scanLibraryArtifacts(baseDir: state.baseDirectory)
                        let downloadedPackages = checkDownloadedPackages(in: state.baseDirectory)

                        // Update package download status
                        for index in state.packages.indices {
                            let pkg = state.packages[index].package
                            let isDownloaded = downloadedPackages.contains("\(pkg.owner)/\(pkg.repo)".lowercased())
                            state.packages[index].isDownloaded = isDownloaded
                        }

                        state.statusMessage = "✅ Base directory saved and reloaded: \(state.baseDirectory)"
                    }
                    // Continue to next iteration for render
                }
            }
        }

        // Cleanup terminal
        print(Screen.showCursor, terminator: "")
        fflush(stdout)
        await screen.exitAltScreen()
        await screen.disableRawMode(originalTermios)
        print(Screen.clearScreen + Screen.home, terminator: "")
        fflush(stdout)
    }

    /// Render the current view based on state
    static func renderCurrentView(
        state: AppState,
        rows: Int,
        cols: Int,
        pageSize: Int,
        homeCursor: Int,
        libraryCursor: Int,
        settingsCursor: Int,
        artifacts: [ArtifactInfo],
        homeView: HomeView,
        packageView: PackageView,
        libraryView: LibraryView,
        settingsView: SettingsView
    ) -> String {
        switch state.viewMode {
        case .home:
            let stats = HomeStats(
                totalPackages: state.packages.count,
                selectedPackages: state.packages.filter(\.isSelected).count,
                downloadedPackages: state.packages.filter(\.isDownloaded).count,
                artifactCount: artifacts.count,
                totalSize: artifacts.reduce(0) { $0 + $1.sizeBytes }
            )
            return homeView.render(cursor: homeCursor, width: cols, height: rows, stats: stats)
        case .packages:
            return packageView.render(state: state, width: cols, height: rows)
        case .library:
            return libraryView.render(artifacts: artifacts, cursor: libraryCursor, width: cols, height: rows)
        case .settings:
            return settingsView.render(
                cursor: settingsCursor,
                width: cols,
                height: rows,
                baseDirectory: state.baseDirectory,
                isEditing: state.isEditingSettings,
                editBuffer: state.editBuffer,
                statusMessage: state.statusMessage
            )
        }
    }

    static func openCurrentPackageInBrowser(state: AppState) {
        let visible = state.visiblePackages
        guard state.cursor < visible.count else { return }

        let package = visible[state.cursor].package
        let url = package.url

        // Use macOS 'open' command to open URL in default browser
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url]

        do {
            try process.run()
        } catch {
            // Silently fail - don't crash the TUI
        }
    }

    static func saveSelections(state: AppState) throws {
        let selected = state.packages.filter(\.isSelected).map(\.package)

        // Convert to priority package format
        let priorityPackages = selected.map { pkg in
            PriorityPackage(owner: pkg.owner, repo: pkg.repo, url: pkg.url)
        }

        // Create catalog JSON structure
        let catalogJSON: [String: Any] = [
            "version": "1.0",
            "lastUpdated": ISO8601DateFormatter().string(from: Date()),
            "description": "Curated list of high-priority Swift packages (TUI generated)",
            "tiers": [
                "ecosystem": [
                    "description": "Essential ecosystem packages",
                    "count": priorityPackages.count,
                    "packages": priorityPackages.map { [
                        "owner": $0.owner ?? "",
                        "repo": $0.repo,
                        "url": $0.url,
                    ] },
                ],
            ],
            "stats": [
                "totalPriorityPackages": priorityPackages.count,
            ],
        ]

        // Write to Resources directory
        let data = try JSONSerialization.data(withJSONObject: catalogJSON, options: [.prettyPrinted, .sortedKeys])
        let resourcesPath = CupertinoResources.bundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/Resources/priority-packages.json")

        try data.write(to: resourcesPath)

        state.statusMessage = "✅ Saved \(selected.count) packages"
    }

    /// Check which packages are downloaded in the docs directory
    /// Check downloaded packages using a string path
    static func checkDownloadedPackages(in basePath: String) -> Set<String> {
        let packagesDir = URL(fileURLWithPath: basePath).appendingPathComponent("packages")
        return checkDownloadedPackages(in: packagesDir)
    }

    /// Check downloaded packages in a URL directory
    static func checkDownloadedPackages(in docsDirectory: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: docsDirectory.path) else {
            return []
        }

        var downloaded = Set<String>()

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: docsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for url in contents {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    // Directory name format is typically "owner-repo" or "owner/repo"
                    let dirName = url.lastPathComponent.lowercased()
                    // Handle both formats: "owner/repo" and "owner-repo"
                    let normalized = dirName.replacingOccurrences(of: "-", with: "/")
                    downloaded.insert(normalized)
                    // Also add the original format
                    downloaded.insert(dirName)
                }
            }
        } catch {
            // Silently fail if we can't read the directory
        }

        return downloaded
    }

    /// Scan library for artifacts
    static func scanLibraryArtifacts() -> [ArtifactInfo] {
        scanLibraryArtifactsInDirectory(Shared.Constants.defaultBaseDirectory)
    }

    /// Scan library for artifacts using a string path
    static func scanLibraryArtifacts(baseDir: String) -> [ArtifactInfo] {
        let url = URL(fileURLWithPath: baseDir)
        return scanLibraryArtifactsInDirectory(url)
    }

    /// Scan library for artifacts in a specific base directory
    static func scanLibraryArtifactsInDirectory(_ baseDir: URL) -> [ArtifactInfo] {
        var artifacts: [ArtifactInfo] = []

        let artifactDirs: [(name: String, subpath: String)] = [
            ("Apple Documentation", "docs"),
            ("Swift Evolution", "swift-evolution"),
            ("Swift.org", "swift-org"),
            ("Swift Book", "swift-book"),
            ("Swift Packages", "packages"),
            ("Sample Code", "sample-code"),
        ]

        for (name, subpath) in artifactDirs {
            let path = baseDir.appendingPathComponent(subpath)
            guard FileManager.default.fileExists(atPath: path.path) else {
                continue
            }

            let itemCount = countItems(in: path)
            let size = calculateDirectorySize(path)

            artifacts.append(ArtifactInfo(
                name: name,
                path: path,
                itemCount: itemCount,
                sizeBytes: size
            ))
        }

        return artifacts
    }

    /// Reload artifacts and download status from new base directory
    static func reloadData(state: AppState, newBaseDir: String) -> [ArtifactInfo] {
        let baseDirURL = URL(fileURLWithPath: newBaseDir)

        // Rescan artifacts from new base directory
        let artifacts = scanLibraryArtifactsInDirectory(baseDirURL)

        // Re-check downloaded packages
        let docsDirectory = baseDirURL.appendingPathComponent("docs")
        let downloadedPackages = checkDownloadedPackages(in: docsDirectory)

        // Update package download status
        for index in 0..<state.packages.count {
            let pkg = state.packages[index].package
            let isDownloaded = downloadedPackages.contains("\(pkg.owner)/\(pkg.repo)".lowercased())
            state.packages[index].isDownloaded = isDownloaded
        }

        return artifacts
    }

    static func countItems(in directory: URL) -> Int {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return contents.count
        } catch {
            return 0
        }
    }

    static func calculateDirectorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile,
                  let fileSize = resourceValues.fileSize
            else {
                continue
            }

            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    static func openInFinder(url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]

        do {
            try process.run()
        } catch {
            // Silently fail
        }
    }
}
