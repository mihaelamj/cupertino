import Foundation
import SearchModels

// MARK: - Sample-code per-framework platform availability table

//
// #1104: 633/634 samples landed with all-NULL `min_<platform>`
// columns. Apple's sample catalog ships with mostly-empty
// `deploymentTargets`; the per-sample availability sidecars carry
// per-file `@available` attributes but project-level inference
// requires aggregation. Indexer's
// `Sample.Index.Builder.indexProject` only stamped platforms when
// the project's `Package.swift` declared them — which only 1 of 634
// projects (SlothCreator) does.
//
// This static table maps the top ~30 framework slugs in the samples
// corpus to per-platform introduction versions. When
// `deploymentTargets` is empty, the builder falls back to looking
// up each project's `frameworks` field here.
//
// Lives in SampleIndexModels (foundation tier) so
// `SampleIndex.Builder` can consume it directly.

public enum SampleFrameworkAvailability {
    public static let universalApple = Search.PlatformVersions(
        iOS: "8.0", macOS: "10.9", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"
    )

    /// Lowercased framework slug → platform floor. Match against
    /// `projects.frameworks` field (lowercased) post-trim.
    public static let table: [String: Search.PlatformVersions] = [
        // Language / universal
        "foundation": universalApple,
        "swift": universalApple,

        // UI
        "uikit": .init(iOS: "2.0", macOS: "13.0", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "swiftui": .init(iOS: "13.0", macOS: "10.15", tvOS: "13.0", watchOS: "6.0", visionOS: "1.0"),
        "appkit": .init(iOS: nil, macOS: "10.0", tvOS: nil, watchOS: nil, visionOS: nil),

        // Graphics / media
        "metal": .init(iOS: "8.0", macOS: "10.11", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "metalkit": .init(iOS: "9.0", macOS: "10.11", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "metalfx": .init(iOS: "16.0", macOS: "13.0", tvOS: "16.0", watchOS: nil, visionOS: "1.0"),
        "coreanimation": .init(iOS: "2.0", macOS: "10.5", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "coregraphics": .init(iOS: "2.0", macOS: "10.0", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "coreimage": .init(iOS: "5.0", macOS: "10.4", tvOS: "9.0", watchOS: "5.0", visionOS: "1.0"),
        "coreml": .init(iOS: "11.0", macOS: "10.13", tvOS: "11.0", watchOS: "4.0", visionOS: "1.0"),
        "vision": .init(iOS: "11.0", macOS: "10.13", tvOS: "11.0", watchOS: nil, visionOS: "1.0"),
        "videotoolbox": .init(iOS: "6.0", macOS: "10.8", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "avfoundation": .init(iOS: "4.0", macOS: "10.7", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "avfaudio": .init(iOS: "3.0", macOS: "10.7", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "avkit": .init(iOS: "8.0", macOS: "10.10", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),

        // AR / spatial
        "arkit": .init(iOS: "11.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "realitykit": .init(iOS: "13.0", macOS: "10.15", tvOS: "13.0", watchOS: nil, visionOS: "1.0"),
        "visionos": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "tabletopkit": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.0"),

        // Photos / Media / Maps
        "photokit": .init(iOS: "8.0", macOS: "10.11", tvOS: "10.0", watchOS: nil, visionOS: "1.0"),
        "mapkit": .init(iOS: "3.0", macOS: "10.9", tvOS: "9.2", watchOS: "2.0", visionOS: "1.0"),

        // Health, fitness
        "healthkit": .init(iOS: "8.0", macOS: "13.0", tvOS: nil, watchOS: "2.0", visionOS: "1.0"),

        // Audio
        "coreaudio": universalApple,
        "corehaptics": .init(iOS: "13.0", macOS: "10.15", tvOS: "14.0", watchOS: nil, visionOS: "1.0"),

        // Intents / Commerce / Maps / System
        "sirikit": .init(iOS: "10.0", macOS: "10.12", tvOS: nil, watchOS: "3.2", visionOS: "1.0"),
        "storekit": .init(iOS: "3.0", macOS: "10.7", tvOS: "9.0", watchOS: "6.2", visionOS: "1.0"),
        "accessibility": .init(iOS: "5.0", macOS: "10.5", tvOS: "9.0", watchOS: "4.0", visionOS: "1.0"),
        "safariservices": .init(iOS: "7.0", macOS: "10.10", tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "networkextension": .init(iOS: "8.0", macOS: "10.10", tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "coredata": .init(iOS: "3.0", macOS: "10.4", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "accelerate": .init(iOS: "4.0", macOS: "10.3", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),

        // tvOS-only
        "tvservices": .init(iOS: nil, macOS: nil, tvOS: "9.0", watchOS: nil, visionOS: nil),
        "tvmljs": .init(iOS: nil, macOS: nil, tvOS: "9.0", watchOS: nil, visionOS: nil),

        // Xcode tooling
        "xcode": .init(iOS: nil, macOS: "10.0", tvOS: nil, watchOS: nil, visionOS: nil),
    ]

    /// Lookup with normalization (lowercase + trim + comma-first-of).
    /// Returns universal Apple baseline for unknown frameworks.
    public static func versions(for framework: String) -> Search.PlatformVersions {
        let trimmed = framework.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = table[trimmed] { return exact }
        if trimmed.contains(",") {
            let first = trimmed.split(separator: ",").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? trimmed
            if let exact = table[first] { return exact }
        }
        return universalApple
    }
}
