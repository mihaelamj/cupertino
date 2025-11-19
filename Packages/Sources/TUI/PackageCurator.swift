import Core
import Foundation
import Resources

@main
struct PackageCuratorApp {
    static func main() async throws {
        // Load packages
        let packages = await SwiftPackagesCatalog.allPackages
        let priorityURLs = await PriorityPackagesCatalog.allPackages.map(\.url)

        // Initialize state
        let state = AppState()
        state.packages = packages.map { pkg in
            let isSelected = priorityURLs.contains(pkg.url)
            return PackageEntry(package: pkg, isSelected: isSelected)
        }

        // Initialize UI components
        let screen = Screen()
        let input = Input()
        let view = PackageView()

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

            // Render (always render to update on resize)
            let content = view.render(state: state, width: cols, height: rows)
            await screen.render(content)

            // Handle input (non-blocking with 0.1s timeout in terminal)
            if let key = input.readKey() {
                let pageSize = rows - 4

                // Search mode handling
                if state.isSearching {
                    switch key {
                    case .escape, .enter:
                        state.isSearching = false
                    case .backspace:
                        if !state.searchQuery.isEmpty {
                            state.searchQuery.removeLast()
                            state.cursor = 0
                            state.scrollOffset = 0
                        }
                    case let .char(ch) where ch.isLetter || ch.isNumber || ch.isWhitespace || "-_./".contains(ch):
                        state.searchQuery.append(ch)
                        state.cursor = 0
                        state.scrollOffset = 0
                    default:
                        break
                    }
                } else {
                    // Normal mode handling
                    switch key {
                    case .arrowUp, .char("k"):
                        state.moveCursor(delta: -1, pageSize: pageSize)
                    case .arrowDown, .char("j"):
                        state.moveCursor(delta: 1, pageSize: pageSize)
                    case .arrowLeft, .pageUp:
                        state.moveCursor(delta: -pageSize, pageSize: pageSize)
                    case .arrowRight, .pageDown:
                        state.moveCursor(delta: pageSize, pageSize: pageSize)
                    case .homeKey, .ctrl("a"):
                        state.moveCursor(delta: -state.cursor, pageSize: pageSize)
                    case .endKey, .ctrl("e"):
                        let lastIndex = state.visiblePackages.count - 1
                        state.moveCursor(delta: lastIndex - state.cursor, pageSize: pageSize)
                    case .space:
                        state.toggleCurrent()
                    case .char("s"):
                        state.cycleSortMode()
                    case .char("w"):
                        try saveSelections(state: state)
                    case .char("/"):
                        state.isSearching = true
                    case .char("o"), .enter:
                        openCurrentPackageInBrowser(state: state)
                    case .char("q"), .ctrl("c"), .escape:
                        running = false
                    default:
                        break
                    }
                }
            }
            // No sleep needed - terminal timeout provides ~10 FPS natural rate
        }

        // Cleanup terminal
        await screen.exitAltScreen()
        await screen.disableRawMode(originalTermios)
        print(Screen.showCursor)
        fflush(stdout)
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
}
