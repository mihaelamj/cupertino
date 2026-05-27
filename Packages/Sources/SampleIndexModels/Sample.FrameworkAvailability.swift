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
// This static table maps the framework slugs in the samples corpus
// to per-platform introduction versions. When `deploymentTargets`
// is empty, the builder falls back to looking up each project's
// `frameworks` field here.
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
        "swiftdata": .init(iOS: "17.0", macOS: "14.0", tvOS: "17.0", watchOS: "10.0", visionOS: "1.0"),
        "widgetkit": .init(iOS: "14.0", macOS: "11.0", tvOS: "17.0", watchOS: "9.0", visionOS: "1.0"),
        "pencilkit": .init(iOS: "13.0", macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: "1.0"),

        // Graphics / media
        "metal": .init(iOS: "8.0", macOS: "10.11", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "metalkit": .init(iOS: "9.0", macOS: "10.11", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "metalfx": .init(iOS: "16.0", macOS: "13.0", tvOS: "16.0", watchOS: nil, visionOS: "1.0"),
        "metalperformanceshadersgraph": .init(
            iOS: "14.0", macOS: "11.0", tvOS: "14.0", watchOS: nil, visionOS: "1.0"
        ),
        "coreanimation": .init(iOS: "2.0", macOS: "10.5", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "coregraphics": .init(iOS: "2.0", macOS: "10.0", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "coreimage": .init(iOS: "5.0", macOS: "10.4", tvOS: "9.0", watchOS: "5.0", visionOS: "1.0"),
        "coreml": .init(iOS: "11.0", macOS: "10.13", tvOS: "11.0", watchOS: "4.0", visionOS: "1.0"),
        "vision": .init(iOS: "11.0", macOS: "10.13", tvOS: "11.0", watchOS: nil, visionOS: "1.0"),
        "videotoolbox": .init(iOS: "6.0", macOS: "10.8", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "avfoundation": .init(iOS: "4.0", macOS: "10.7", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "avfaudio": .init(iOS: "3.0", macOS: "10.7", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "avkit": .init(iOS: "8.0", macOS: "10.10", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "createml": .init(iOS: "15.0", macOS: "10.14", tvOS: nil, watchOS: nil, visionOS: nil),

        // AR / spatial
        "arkit": .init(iOS: "11.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "realitykit": .init(iOS: "13.0", macOS: "10.15", tvOS: "13.0", watchOS: nil, visionOS: "1.0"),
        "visionos": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "tabletopkit": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "roomplan": .init(iOS: "16.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil),

        // Photos / Media / Maps
        "photokit": .init(iOS: "8.0", macOS: "10.11", tvOS: "10.0", watchOS: nil, visionOS: "1.0"),
        "mapkit": .init(iOS: "3.0", macOS: "10.9", tvOS: "9.2", watchOS: "2.0", visionOS: "1.0"),

        // Health, fitness
        "healthkit": .init(iOS: "8.0", macOS: "13.0", tvOS: nil, watchOS: "2.0", visionOS: "1.0"),

        // Audio / haptics
        "coreaudio": .init(iOS: "2.0", macOS: "10.4", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "audiotoolbox": .init(iOS: "2.0", macOS: "10.5", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "corehaptics": .init(iOS: "13.0", macOS: "10.15", tvOS: "14.0", watchOS: nil, visionOS: "1.0"),

        // Intents / Commerce / Maps / System
        "sirikit": .init(iOS: "10.0", macOS: "10.12", tvOS: nil, watchOS: "3.2", visionOS: "1.0"),
        "appintents": .init(
            iOS: "16.0", macOS: "13.0", tvOS: nil, watchOS: "9.0", visionOS: "1.0"
        ),
        "storekit": .init(iOS: "3.0", macOS: "10.7", tvOS: "9.0", watchOS: "6.2", visionOS: "1.0"),
        "accessibility": .init(iOS: "5.0", macOS: "10.5", tvOS: "9.0", watchOS: "4.0", visionOS: "1.0"),
        "safariservices": .init(iOS: "7.0", macOS: "10.10", tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "networkextension": .init(iOS: "8.0", macOS: "10.10", tvOS: nil, watchOS: nil, visionOS: nil),
        "coredata": .init(iOS: "3.0", macOS: "10.4", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "accelerate": .init(iOS: "4.0", macOS: "10.3", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "carplay": .init(iOS: "12.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil),
        "homekit": .init(iOS: "8.0", macOS: nil, tvOS: "10.0", watchOS: "2.0", visionOS: "1.0"),
        "corenfc": .init(iOS: "11.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil),

        // Connectivity / discovery
        "network": .init(iOS: "12.0", macOS: "10.14", tvOS: "12.0", watchOS: "5.0", visionOS: "1.0"),
        "cryptokit": .init(iOS: "13.0", macOS: "10.15", tvOS: "13.0", watchOS: "6.0", visionOS: "1.0"),
        "nearbyinteraction": .init(
            iOS: "14.0", macOS: nil, tvOS: nil, watchOS: "9.0", visionOS: "1.0"
        ),
        "authenticationservices": .init(
            iOS: "12.0", macOS: "10.15", tvOS: "13.0", watchOS: "6.0", visionOS: "1.0"
        ),
        "groupactivities": .init(
            iOS: "15.0", macOS: "12.0", tvOS: "15.0", watchOS: nil, visionOS: "1.0"
        ),

        // Misc
        "eventkit": .init(iOS: "4.0", macOS: "10.8", tvOS: nil, watchOS: "2.0", visionOS: "1.0"),
        "gamekit": .init(iOS: "3.0", macOS: "10.8", tvOS: "9.0", watchOS: "3.0", visionOS: "1.0"),
        "corelocation": .init(iOS: "2.0", macOS: "10.6", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "usernotifications": .init(
            iOS: "10.0", macOS: "10.14", tvOS: "10.0", watchOS: "3.0", visionOS: "1.0"
        ),
        "applearchive": .init(
            iOS: "14.0", macOS: "11.0", tvOS: "14.0", watchOS: "7.0", visionOS: "1.0"
        ),
        "kernel": .init(iOS: nil, macOS: "10.0", tvOS: nil, watchOS: nil, visionOS: nil),

        // watchOS apps shell
        "watchos-apps": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: "2.0", visionOS: nil),
        "clockkit": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: "2.0", visionOS: nil),

        // Virtualization / hypervisor (macOS-only)
        "virtualization": .init(iOS: nil, macOS: "11.0", tvOS: nil, watchOS: nil, visionOS: nil),

        // tvOS-only
        "tvservices": .init(iOS: nil, macOS: nil, tvOS: "9.0", watchOS: nil, visionOS: nil),
        "tvmljs": .init(iOS: nil, macOS: nil, tvOS: "9.0", watchOS: nil, visionOS: nil),

        // Xcode tooling
        "xcode": .init(iOS: nil, macOS: "10.0", tvOS: nil, watchOS: nil, visionOS: nil),

        // Common iOS-leaning frameworks (long-tail single-sample frameworks)
        "webkit": .init(iOS: "8.0", macOS: "10.10", tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "cloudkit": .init(iOS: "8.0", macOS: "10.10", tvOS: "9.0", watchOS: "3.0", visionOS: "1.0"),
        "contacts": .init(iOS: "9.0", macOS: "10.11", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "scenekit": .init(iOS: "8.0", macOS: "10.8", tvOS: "9.0", watchOS: "4.0", visionOS: "1.0"),
        "passkit": .init(iOS: "6.0", macOS: "11.0", tvOS: nil, watchOS: "2.0", visionOS: "1.0"),
        "pdfkit": .init(iOS: "11.0", macOS: "10.4", tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "messages": .init(iOS: "10.0", macOS: "10.12", tvOS: nil, watchOS: nil, visionOS: nil),
        "musickit": .init(iOS: "13.0", macOS: "11.0", tvOS: "14.0", watchOS: "7.0", visionOS: "1.0"),
        "charts": .init(iOS: "16.0", macOS: "13.0", tvOS: "16.0", watchOS: "9.0", visionOS: "1.0"),
        "speech": .init(iOS: "10.0", macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "callkit": .init(iOS: "10.0", macOS: "11.0", tvOS: nil, watchOS: nil, visionOS: nil),
        "mediaplayer": .init(iOS: "3.0", macOS: "10.12", tvOS: "9.0", watchOS: nil, visionOS: "1.0"),
        "corebluetooth": .init(
            iOS: "5.0", macOS: "10.7", tvOS: "9.0", watchOS: "4.0", visionOS: "1.0"
        ),
        "coremidi": .init(iOS: "4.2", macOS: "10.0", tvOS: "12.0", watchOS: nil, visionOS: "1.0"),
        "coremotion": .init(iOS: "4.0", macOS: "14.0", tvOS: nil, watchOS: "2.0", visionOS: "1.0"),
        "gamecontroller": .init(
            iOS: "7.0", macOS: "10.9", tvOS: "9.0", watchOS: "5.0", visionOS: "1.0"
        ),
        "imageio": .init(iOS: "4.0", macOS: "10.4", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "fileprovider": .init(iOS: "8.0", macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "mailkit": .init(iOS: nil, macOS: "12.0", tvOS: nil, watchOS: nil, visionOS: nil),
        "watchkit": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: "1.0", visionOS: nil),
        "weatherkit": .init(
            iOS: "16.0", macOS: "13.0", tvOS: "16.0", watchOS: "9.0", visionOS: "1.0"
        ),
        "shazamkit": .init(
            iOS: "15.0", macOS: "12.0", tvOS: "15.0", watchOS: "8.0", visionOS: "1.0"
        ),
        "soundanalysis": .init(
            iOS: "13.0", macOS: "10.15", tvOS: "13.0", watchOS: "6.0", visionOS: "1.0"
        ),
        "screencapturekit": .init(iOS: nil, macOS: "12.3", tvOS: nil, watchOS: nil, visionOS: nil),
        "replaykit": .init(iOS: "9.0", macOS: "11.0", tvOS: "10.0", watchOS: nil, visionOS: "1.0"),
        "classkit": .init(iOS: "11.4", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil),
        "visionkit": .init(iOS: "13.0", macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil),
        "tipkit": .init(iOS: "17.0", macOS: "14.0", tvOS: "17.0", watchOS: "10.0", visionOS: "1.0"),
        "backgroundtasks": .init(
            iOS: "13.0", macOS: "11.0", tvOS: "13.0", watchOS: nil, visionOS: "1.0"
        ),
        "backgroundassets": .init(
            iOS: "16.1", macOS: "13.0", tvOS: "16.1", watchOS: nil, visionOS: "1.0"
        ),
        "watchconnectivity": .init(iOS: "9.0", macOS: nil, tvOS: nil, watchOS: "2.0", visionOS: nil),
        "appclip": .init(iOS: "14.0", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil),
        "localauthentication": .init(
            iOS: "8.0", macOS: "10.10", tvOS: nil, watchOS: nil, visionOS: "1.0"
        ),
        "compositorservices": .init(iOS: nil, macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.0"),
        "translation": .init(iOS: "17.4", macOS: "14.4", tvOS: nil, watchOS: nil, visionOS: nil),

        // DriverKit family (macOS-only)
        "driverkit": .init(iOS: nil, macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil),
        "audiodriverkit": .init(iOS: nil, macOS: "12.0", tvOS: nil, watchOS: nil, visionOS: nil),
        "mididriverkit": .init(iOS: nil, macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil),
        "hiddriverkit": .init(iOS: nil, macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil),
        "pcidriverkit": .init(iOS: nil, macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil),
        "usbdriverkit": .init(iOS: nil, macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil),
        "endpointsecurity": .init(iOS: nil, macOS: "10.15", tvOS: nil, watchOS: nil, visionOS: nil),

        // tvOS/tv UI
        "tvuikit": .init(iOS: nil, macOS: nil, tvOS: "12.0", watchOS: nil, visionOS: nil),
        "tvmlkit": .init(iOS: nil, macOS: nil, tvOS: "9.0", watchOS: nil, visionOS: nil),
        "tvml": .init(iOS: nil, macOS: nil, tvOS: "9.0", watchOS: nil, visionOS: nil),

        // Other long-tail entries (universalApple unless otherwise noted)
        "security": .init(iOS: "2.0", macOS: "10.0", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"),
        "metalperformanceshaders": .init(
            iOS: "9.0", macOS: "10.13", tvOS: "9.0", watchOS: nil, visionOS: "1.0"
        ),
        "exposurenotification": .init(iOS: "13.5", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil),
        "proximityreader": .init(iOS: "15.4", macOS: nil, tvOS: nil, watchOS: nil, visionOS: nil),
        "workoutkit": .init(iOS: "17.0", macOS: "14.0", tvOS: nil, watchOS: "10.0", visionOS: nil),
        "browserenginekit": .init(iOS: "17.4", macOS: nil, tvOS: nil, watchOS: nil, visionOS: "1.1"),
        "createmlcomponents": .init(iOS: "16.0", macOS: "13.0", tvOS: nil, watchOS: nil, visionOS: nil),
        "automaticassessmentconfiguration": .init(
            iOS: "13.4", macOS: "10.15.4", tvOS: nil, watchOS: nil, visionOS: nil
        ),
    ]

    /// Lookup result: the matched versions + whether the framework
    /// was an exact match in `table`. Callers that prefer conservative
    /// inference can branch on `isExact` to skip stamping when the
    /// framework is unrecognised (the table can't honestly say
    /// "supports all 5 platforms" for an unknown framework).
    public struct LookupResult: Sendable, Equatable {
        public let versions: Search.PlatformVersions
        public let isExact: Bool

        public init(versions: Search.PlatformVersions, isExact: Bool) {
            self.versions = versions
            self.isExact = isExact
        }
    }

    /// Lookup with normalization (lowercase + trim + comma-first-of).
    /// Returns `(universalApple, isExact: false)` for unknown
    /// frameworks; callers should treat unknown results as
    /// "no inferred platform stamp" rather than stamping all 5.
    public static func versions(for framework: String) -> LookupResult {
        let trimmed = framework.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = table[trimmed] {
            return LookupResult(versions: exact, isExact: true)
        }
        if trimmed.contains(",") {
            let first = trimmed.split(separator: ",").first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? trimmed
            if let exact = table[first] {
                return LookupResult(versions: exact, isExact: true)
            }
        }
        return LookupResult(versions: universalApple, isExact: false)
    }

    /// Synthesize a framework probe from a kebab-case project id when
    /// the catalog entry is missing. Sample-code project ids follow
    /// `<framework>-<rest-of-slug>` (verified against the 622-entry
    /// catalog); the prefix before the first `-` is the framework
    /// slug. Returns nil for non-kebab ids.
    public static func frameworkFromProjectId(_ projectId: String) -> String? {
        let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let dashIdx = trimmed.firstIndex(of: "-") {
            return String(trimmed[..<dashIdx])
        }
        return nil
    }
}
