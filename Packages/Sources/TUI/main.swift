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

        defer {
            Task {
                await screen.exitAltScreen()
                await screen.disableRawMode(originalTermios)
                print(Screen.showCursor)
            }
        }

        var running = true
        while running {
            // Render
            let (rows, cols) = await screen.getSize()
            let content = view.render(state: state, width: cols, height: rows)
            await screen.render(content)

            // Handle input
            if let key = input.readKey() {
                switch key {
                case .up, .char("k"):
                    state.moveCursor(delta: -1, pageSize: rows - 4)
                case .down, .char("j"):
                    state.moveCursor(delta: 1, pageSize: rows - 4)
                case .space:
                    state.toggleCurrent()
                case .char("s"):
                    state.cycleSortMode()
                case .char("w"):
                    try saveSelections(state: state)
                case .char("q"), .ctrl("c"), .escape:
                    running = false
                default:
                    break
                }
            }

            // Small delay to avoid busy loop
            try await Task.sleep(nanoseconds: 16000000) // ~60 FPS
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
