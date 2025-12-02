import Foundation
import Resources
import Shared

/// Entry representing an archive guide in the TUI
struct ArchiveEntry {
    let title: String
    let framework: String
    let category: String
    let path: String
    let description: String
    var isSelected: Bool
    var isDownloaded: Bool
    var isRequired: Bool // Cannot be deselected if true

    /// Full URL to the archive guide
    var url: URL? {
        URL(string: "https://developer.apple.com/library/archive/documentation/\(path)")
    }
}

/// Catalog of archive guides loaded from bundled JSON resource
enum ArchiveGuidesCatalog {
    /// User-writable location for selected guides: ~/.cupertino/selected-archive-guides.json
    private static var userSelectionsURL: URL {
        Shared.Constants.defaultBaseDirectory.appendingPathComponent("selected-archive-guides.json")
    }

    /// All archive guides from the bundled catalog
    static var allGuides: [ArchiveEntry] {
        guard let url = CupertinoResources.bundle.url(
            forResource: "archive-guides-catalog",
            withExtension: "json"
        ) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(ArchiveGuidesCatalogJSON.self, from: data)
            return catalog.guides.map { guide in
                ArchiveEntry(
                    title: guide.title,
                    framework: guide.framework,
                    category: guide.category,
                    path: guide.path,
                    description: guide.description,
                    isSelected: guide.required, // Required entries start selected
                    isDownloaded: false,
                    isRequired: guide.required
                )
            }
        } catch {
            return []
        }
    }

    /// Load selected guides from user-writable location (~/.cupertino/selected-archive-guides.json)
    /// If file doesn't exist, creates it from bundled catalog with required guides selected
    static func loadSelectedGuidePaths() -> Set<String> {
        let selectedURL = userSelectionsURL

        // If user file doesn't exist, create it from bundled catalog
        if !FileManager.default.fileExists(atPath: selectedURL.path) {
            createDefaultSelectionsFile()
        }

        guard FileManager.default.fileExists(atPath: selectedURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: selectedURL)
            let selected = try JSONDecoder().decode(SelectedArchiveGuidesJSON.self, from: data)
            return Set(selected.guides.map(\.path))
        } catch {
            return []
        }
    }

    /// Create default selections file from bundled catalog (required guides only)
    private static func createDefaultSelectionsFile() {
        guard let bundleURL = CupertinoResources.bundle.url(
            forResource: "archive-guides-catalog",
            withExtension: "json"
        ) else {
            return
        }

        do {
            // Ensure ~/.cupertino directory exists
            let baseDir = Shared.Constants.defaultBaseDirectory
            if !FileManager.default.fileExists(atPath: baseDir.path) {
                try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            }

            // Load bundled catalog and extract required guides
            let data = try Data(contentsOf: bundleURL)
            let catalog = try JSONDecoder().decode(ArchiveGuidesCatalogJSON.self, from: data)
            let requiredGuides = catalog.guides.filter(\.required)

            // Create selections JSON with required guides
            let json = SelectedArchiveGuidesJSON(
                version: "1.0",
                lastUpdated: ISO8601DateFormatter().string(from: Date()),
                description: "Selected Apple Archive guides for crawling (auto-generated with required guides)",
                count: requiredGuides.count,
                guides: requiredGuides.map { guide in
                    SelectedGuideJSON(
                        title: guide.title,
                        framework: guide.framework,
                        category: guide.category,
                        path: guide.path
                    )
                }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let outputData = try encoder.encode(json)
            try outputData.write(to: userSelectionsURL)
        } catch {
            // Silently fail - will fall back to bundled defaults
        }
    }

    /// Save selected guides to user-writable location
    static func saveSelectedGuides(_ guides: [ArchiveEntry]) throws {
        // Ensure ~/.cupertino directory exists
        let baseDir = Shared.Constants.defaultBaseDirectory
        if !FileManager.default.fileExists(atPath: baseDir.path) {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }

        let selected = guides.filter(\.isSelected)
        let json = SelectedArchiveGuidesJSON(
            version: "1.0",
            lastUpdated: ISO8601DateFormatter().string(from: Date()),
            description: "Selected Apple Archive guides for crawling (TUI generated)",
            count: selected.count,
            guides: selected.map { guide in
                SelectedGuideJSON(
                    title: guide.title,
                    framework: guide.framework,
                    category: guide.category,
                    path: guide.path
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(json)
        try data.write(to: userSelectionsURL)
    }
}

// MARK: - JSON Codable Types

private struct ArchiveGuidesCatalogJSON: Codable {
    let count: Int
    let guides: [ArchiveGuideJSON]
    let baseURL: String
}

private struct ArchiveGuideJSON: Codable {
    let title: String
    let framework: String
    let category: String
    let path: String
    let description: String
    let required: Bool
}

private struct SelectedArchiveGuidesJSON: Codable {
    let version: String
    let lastUpdated: String
    let description: String
    let count: Int
    let guides: [SelectedGuideJSON]
}

private struct SelectedGuideJSON: Codable {
    let title: String
    let framework: String
    let category: String
    let path: String
}
