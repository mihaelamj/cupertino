import CoreProtocols
import CrawlerModels
import Foundation
import Resources
import SharedConstants
// MARK: - Archive Guide Catalog

extension Crawler {
    /// Curated catalog of essential Apple Archive documentation guides
    /// These are classic guides that contain foundational knowledge not available elsewhere.
    ///
    /// Post-#535: every accessor that touches the user-writable selections
    /// file takes a `baseDirectory: URL` parameter so callers thread the
    /// resolved per-install base directory from their composition root
    /// (`Shared.Paths.live().baseDirectory` in CLI, an explicit `tempDir`
    /// in tests). The previous shape used `Shared.Constants.defaultBaseDirectory`
    /// internally, which routed through `BinaryConfig.shared` (Service
    /// Locator). Pure accessors that need no on-disk path (`testGuides`,
    /// `getRequiredGuidePaths`) keep their argumentless surface.
    public enum ArchiveGuideCatalog {
        /// Base URL for Apple's documentation archive (no trailing slash;
        /// derived from `Shared.Constants.BaseURL.appleArchiveDocs` so the
        /// canonical form lives in one place).
        private static let baseURL = String(Shared.Constants.BaseURL.appleArchiveDocs.dropLast())

        /// User-writable location for selected guides under the supplied base directory.
        private static func userSelectionsURL(baseDirectory: URL) -> URL {
            baseDirectory.appendingPathComponent("selected-archive-guides.json")
        }

        /// Essential programming guides worth crawling
        /// Always reads from user-writable location (creates from bundled if missing).
        public static func essentialGuides(baseDirectory: URL) -> [URL] {
            essentialGuidesWithInfo(baseDirectory: baseDirectory).map(\.url)
        }

        /// Essential guides with full info (URL + framework)
        /// Always reads from user-writable location (creates from bundled if missing).
        public static func essentialGuidesWithInfo(baseDirectory: URL) -> [AppleArchive.GuideInfo] {
            // Ensure user selections file exists (creates from bundled if missing)
            ensureUserSelectionsFileExists(baseDirectory: baseDirectory)

            // Load from user selections file
            if let selectedGuides = loadUserSelectedGuides(baseDirectory: baseDirectory), !selectedGuides.isEmpty {
                return selectedGuides.compactMap { guide in
                    guard let url = URL(string: "\(baseURL)/\(guide.path)") else { return nil }
                    return AppleArchive.GuideInfo(url: url, framework: guide.framework)
                }
            }

            // Fall back to hardcoded list if everything else fails (no framework info)
            return essentialGuidePaths.compactMap { path in
                guard let url = URL(string: "\(baseURL)/\(path)") else { return nil }
                return AppleArchive.GuideInfo(url: url, framework: "")
            }
        }

        /// Load selected guides with full info from user file
        private static func loadUserSelectedGuides(baseDirectory: URL) -> [SelectedGuideJSON]? {
            let selectedURL = userSelectionsURL(baseDirectory: baseDirectory)

            guard FileManager.default.fileExists(atPath: selectedURL.path) else {
                return nil
            }

            do {
                let data = try Data(contentsOf: selectedURL)
                let json = try JSONDecoder().decode(SelectedArchiveGuidesJSON.self, from: data)
                return json.guides
            } catch {
                return nil
            }
        }

        /// Ensure user selections file exists, creating from bundled catalog if missing
        private static func ensureUserSelectionsFileExists(baseDirectory: URL) {
            let selectedURL = userSelectionsURL(baseDirectory: baseDirectory)

            // If file already exists, nothing to do
            if FileManager.default.fileExists(atPath: selectedURL.path) {
                return
            }

            // Load embedded catalog and create user file with required guides (#161)
            guard let data = Resources.jsonData(named: "archive-guides-catalog") else {
                return
            }

            do {
                // Ensure the base directory exists
                if !FileManager.default.fileExists(atPath: baseDirectory.path) {
                    try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
                }

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
                try outputData.write(to: selectedURL)
            } catch {
                // Silently fail - will fall back to hardcoded defaults
            }
        }

        /// Load selected guides from the user-writable location under the supplied base directory.
        private static func loadUserSelectedGuidePaths(baseDirectory: URL) -> [String]? {
            let selectedURL = userSelectionsURL(baseDirectory: baseDirectory)

            guard FileManager.default.fileExists(atPath: selectedURL.path) else {
                return nil
            }

            do {
                let data = try Data(contentsOf: selectedURL)
                let json = try JSONDecoder().decode(SelectedArchiveGuidesJSON.self, from: data)
                return json.guides.map(\.path)
            } catch {
                return nil
            }
        }

        /// Load guides from embedded catalog JSON (used for fallback).
        private static func loadBundledCatalogPaths() -> [String]? {
            guard let data = Resources.jsonData(named: "archive-guides-catalog") else {
                return nil
            }

            do {
                let json = try JSONDecoder().decode(ArchiveGuidesCatalogJSON.self, from: data)
                return json.guides.map(\.path)
            } catch {
                return nil
            }
        }

        /// Path components for essential guides (relative to base documentation URL)
        private static let essentialGuidePaths: [String] = [
            // MARK: - Tier 1: Core Language & Runtime (still highly relevant)

            // Objective-C Runtime - essential for understanding iOS/macOS internals
            "Cocoa/Conceptual/ObjCRuntimeGuide",

            // Key-Value Observing - fundamental pattern, still used
            "Cocoa/Conceptual/KeyValueObserving",

            // Key-Value Coding - foundation for bindings and many frameworks
            "Cocoa/Conceptual/KeyValueCoding",

            // Memory Management - essential for understanding ARC behavior
            "Cocoa/Conceptual/MemoryMgmt",

            // MARK: - Tier 2: Cocoa Fundamentals (timeless concepts)

            // Cocoa Fundamentals - comprehensive intro to Cocoa
            "Cocoa/Conceptual/CocoaFundamentals",

            // Coding Guidelines - Apple's official naming conventions
            "Cocoa/Conceptual/CodingGuidelines",

            // Exception Programming - Objective-C exception handling
            "Cocoa/Conceptual/Exceptions",

            // Threading Programming Guide - foundational concurrency concepts
            "Cocoa/Conceptual/Multithreading",

            // MARK: - Tier 3: Application Architecture

            // App Programming Guide for iOS - architecture patterns
            "iPhone/Conceptual/iPhoneOSProgrammingGuide",

            // Mac App Programming Guide
            "General/Conceptual/MOSXAppProgrammingGuide",

            // View Controller Programming Guide for iOS
            "iPhone/Conceptual/ViewControllerPGforiPhoneOS",

            // Table View Programming Guide for iOS
            "UserExperience/Conceptual/TableView_iPhone",

            // MARK: - Tier 4: Data & Persistence

            // Core Data Programming Guide
            "Cocoa/Conceptual/CoreData",

            // Property List Programming Guide
            "Cocoa/Conceptual/PropertyLists",

            // Archives and Serializations
            "Cocoa/Conceptual/Archiving",

            // MARK: - Tier 5: Graphics & Animation

            // Quartz 2D Programming Guide - foundational graphics
            "GraphicsImaging/Conceptual/drawingwithquartz2d",

            // Core Animation Programming Guide
            "Cocoa/Conceptual/CoreAnimation_guide",

            // Animation Types and Timing Programming Guide
            "Cocoa/Conceptual/Animation_Types_Timing",

            // MARK: - Tier 6: Text & Strings

            // String Programming Guide
            "Cocoa/Conceptual/Strings",

            // Attributed String Programming Guide
            "Cocoa/Conceptual/AttributedStrings",

            // Text System Overview
            "Cocoa/Conceptual/TextArchitecture",

            // MARK: - Tier 7: Collections & Data Structures

            // Collections Programming Topics
            "Cocoa/Conceptual/Collections",

            // Number and Value Programming Topics
            "Cocoa/Conceptual/NumbersandValues",

            // Date and Time Programming Guide
            "Cocoa/Conceptual/DatesAndTimes",

            // MARK: - Tier 8: System Services

            // File System Programming Guide
            "FileManagement/Conceptual/FileSystemProgrammingGuide",

            // Networking Overview
            "NetworkingInternetWeb/Conceptual/NetworkingOverview",

            // URL Session Programming Guide
            "Cocoa/Conceptual/URLLoadingSystem",

            // MARK: - Tier 9: User Interface

            // Auto Layout Guide
            "UserExperience/Conceptual/AutolayoutPG",

            // Human Interface Guidelines (older but foundational)
            "UserExperience/Conceptual/MobileHIG",

            // View Programming Guide for iOS
            "WindowsViews/Conceptual/ViewPG_iPhoneOS",

            // MARK: - Tier 10: Performance & Debugging

            // Instruments User Guide
            "DeveloperTools/Conceptual/InstrumentsUserGuide",

            // Performance Overview
            "Performance/Conceptual/PerformanceOverview",

            // Debugging with Xcode
            "DeveloperTools/Conceptual/debugging_with_xcode",

            // MARK: - Tier 11: Security

            // Secure Coding Guide
            "Security/Conceptual/SecureCodingGuide",

            // Keychain Services Programming Guide
            "Security/Conceptual/keychainServConcepts",

            // MARK: - Tier 12: Internationalization

            // Internationalization and Localization Guide
            "MacOSX/Conceptual/BPInternational",

            // MARK: - Tier 13: Bundles & Resources

            // Bundle Programming Guide
            "CoreFoundation/Conceptual/CFBundles",

            // Resource Programming Guide
            "Cocoa/Conceptual/LoadingResources",

            // MARK: - Tier 14: Other Essential Topics

            // Notification Programming Topics
            "Cocoa/Conceptual/Notifications",

            // Timer Programming Topics
            "Cocoa/Conceptual/Timers",

            // Error Handling Programming Guide
            "Cocoa/Conceptual/ErrorHandlingCocoa",

            // Predicate Programming Guide
            "Cocoa/Conceptual/Predicates",
        ]

        /// Quick test guides - use for testing the crawler with minimal downloads
        public static var testGuides: [URL] {
            [
                // Just the Objective-C Runtime Guide - well-structured, moderate size
                try! URL(knownGood: "\(baseURL)/Cocoa/Conceptual/ObjCRuntimeGuide"),
            ]
        }

        // MARK: - Testing Support

        /// Check if user selections file exists under the supplied base directory.
        public static func userSelectionsFileExists(baseDirectory: URL) -> Bool {
            FileManager.default.fileExists(atPath: userSelectionsURL(baseDirectory: baseDirectory).path)
        }

        /// Get the user selections file URL (for testing) under the supplied base directory.
        public static func userSelectionsFileURL(baseDirectory: URL) -> URL {
            userSelectionsURL(baseDirectory: baseDirectory)
        }

        /// Delete the user selections file (for testing cleanup) under the supplied base directory.
        public static func deleteUserSelectionsFile(baseDirectory: URL) throws {
            let url = userSelectionsURL(baseDirectory: baseDirectory)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }

        /// Load required guide paths from embedded catalog (used by tests).
        public static func getRequiredGuidePaths() -> [String] {
            guard let data = Resources.jsonData(named: "archive-guides-catalog") else {
                return []
            }

            do {
                let json = try JSONDecoder().decode(ArchiveGuidesCatalogJSON.self, from: data)
                return json.guides.filter(\.required).map(\.path)
            } catch {
                return []
            }
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
}
