import Core
import Foundation
import Resources
import Shared

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

/// User-writable location for selected packages: ~/.cupertino/selected-packages.json
private var userPackageSelectionsURL: URL {
    Shared.Constants.defaultBaseDirectory
        .appendingPathComponent(Shared.Constants.FileName.selectedPackages)
}

/// Load selected package URLs from user file (~/.cupertino/selected-packages.json)
/// Returns empty set if file doesn't exist (will use bundled priority-packages.json defaults)
func loadUserSelectedPackageURLs() -> Set<String> {
    let fileURL = userPackageSelectionsURL

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return []
    }

    do {
        let data = try Data(contentsOf: fileURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tiers = json["tiers"] as? [String: Any] else {
            return []
        }

        var urls = Set<String>()
        for (_, tierValue) in tiers {
            if let tier = tierValue as? [String: Any],
               let packages = tier["packages"] as? [[String: Any]] {
                for pkg in packages {
                    if let url = pkg["url"] as? String {
                        urls.insert(url)
                    }
                }
            }
        }
        return urls
    } catch {
        return []
    }
}

/// Save selected packages to ~/.cupertino/selected-packages.json
@MainActor
func saveSelections(state: AppState) throws {
    let selected = state.packages.filter(\.isSelected).map(\.package)

    // Convert to priority package format
    let priorityPackages = selected.map { pkg in
        PriorityPackage(owner: pkg.owner, repo: pkg.repo, url: pkg.url)
    }

    // Create catalog JSON structure matching PriorityPackagesCatalogJSON format
    let catalogJSON: [String: Any] = [
        "version": "1.0",
        "lastUpdated": ISO8601DateFormatter().string(from: Date()),
        "description": "Curated list of high-priority Swift packages (TUI generated)",
        "tiers": [
            "apple_official": [
                "description": "Apple official packages",
                "owner": "apple",
                "count": 0,
                "packages": [] as [[String: Any]],
            ],
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
            "totalCriticalApplePackages": 0,
            "totalEcosystemPackages": priorityPackages.count,
            "totalPriorityPackages": priorityPackages.count,
        ],
    ]

    // Ensure ~/.cupertino directory exists
    let baseDir = Shared.Constants.defaultBaseDirectory
    if !FileManager.default.fileExists(atPath: baseDir.path) {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    // Write to user-writable location
    let data = try JSONSerialization.data(withJSONObject: catalogJSON, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: userPackageSelectionsURL)

    state.statusMessage = "✅ Saved \(selected.count) packages to ~/.cupertino/"
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
