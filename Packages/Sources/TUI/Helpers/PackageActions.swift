import Core
import Foundation
import Resources

/// Open a package's GitHub page in the default browser
@MainActor
func openCurrentPackageInBrowser(state: AppState) {
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

/// Save selected packages to priority-packages.json
@MainActor
func saveSelections(state: AppState) throws {
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

/// Open a URL (file or directory) in Finder
func openInFinder(url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.path]

    do {
        try process.run()
    } catch {
        // Silently fail
    }
}
