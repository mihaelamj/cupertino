import Foundation
@testable import SampleIndexModels
import SearchModels
import Testing

/// #1104 pinning tests for `SampleFrameworkAvailability`.
///
/// Sibling class of #1080's `Issue1080AppleArchiveFrameworkAvailabilityTests`.
/// Pre-#1104 the apple-sample-code per-source DB shipped with 633/634
/// projects carrying all-NULL platform columns; this static table is the
/// load-bearing source of truth that prevents regression.
@Suite("#1104 SampleFrameworkAvailability")
struct Issue1104SampleFrameworkAvailabilityTests {
    @Test("AppKit returns macOS only (no iOS/tvOS/watchOS/visionOS)")
    func appKitMacOSOnly() {
        let result = SampleFrameworkAvailability.versions(for: "AppKit")
        #expect(result.isExact)
        #expect(result.versions.iOS == nil)
        #expect(result.versions.macOS == "10.0")
        #expect(result.versions.tvOS == nil)
        #expect(result.versions.watchOS == nil)
        #expect(result.versions.visionOS == nil)
    }

    @Test("ARKit returns iOS + visionOS (no macOS/tvOS/watchOS)")
    func arkitiOSAndVisionOSOnly() {
        let result = SampleFrameworkAvailability.versions(for: "ARKit")
        #expect(result.isExact)
        #expect(result.versions.iOS == "11.0")
        #expect(result.versions.macOS == nil)
        #expect(result.versions.tvOS == nil)
        #expect(result.versions.watchOS == nil)
        #expect(result.versions.visionOS == "1.0")
    }

    @Test("SwiftUI returns all 5 platforms with correct versions")
    func swiftUIAllPlatforms() {
        let result = SampleFrameworkAvailability.versions(for: "SwiftUI")
        #expect(result.isExact)
        #expect(result.versions.iOS == "13.0")
        #expect(result.versions.macOS == "10.15")
        #expect(result.versions.tvOS == "13.0")
        #expect(result.versions.watchOS == "6.0")
        #expect(result.versions.visionOS == "1.0")
    }

    @Test("CarPlay returns iOS only (12.0)")
    func carPlayiOSOnly() {
        let result = SampleFrameworkAvailability.versions(for: "CarPlay")
        #expect(result.isExact)
        #expect(result.versions.iOS == "12.0")
        #expect(result.versions.macOS == nil)
        #expect(result.versions.tvOS == nil)
        #expect(result.versions.watchOS == nil)
        #expect(result.versions.visionOS == nil)
    }

    @Test("Virtualization returns macOS only")
    func virtualizationMacOSOnly() {
        let result = SampleFrameworkAvailability.versions(for: "Virtualization")
        #expect(result.isExact)
        #expect(result.versions.iOS == nil)
        #expect(result.versions.macOS == "11.0")
        #expect(result.versions.tvOS == nil)
        #expect(result.versions.watchOS == nil)
        #expect(result.versions.visionOS == nil)
    }

    @Test("WatchOS-apps + ClockKit return watchOS only")
    func watchOnlyFrameworks() {
        let apps = SampleFrameworkAvailability.versions(for: "watchOS-apps")
        #expect(apps.isExact)
        #expect(apps.versions.iOS == nil)
        #expect(apps.versions.macOS == nil)
        #expect(apps.versions.watchOS == "2.0")

        let clock = SampleFrameworkAvailability.versions(for: "ClockKit")
        #expect(clock.isExact)
        #expect(clock.versions.iOS == nil)
        #expect(clock.versions.watchOS == "2.0")
    }

    @Test("Unknown framework returns universalApple with isExact = false")
    func unknownFrameworkInexact() {
        let result = SampleFrameworkAvailability.versions(for: "TotallyMadeUpFrameworkKit")
        #expect(!result.isExact)
        #expect(result.versions == SampleFrameworkAvailability.universalApple)
    }

    @Test("Comma-joined framework value uses first entry")
    func commaJoinedTakesFirst() {
        let result = SampleFrameworkAvailability.versions(for: "ARKit, RealityKit")
        #expect(result.isExact)
        #expect(result.versions.iOS == "11.0")
        #expect(result.versions.macOS == nil)
    }

    @Test("Lookup is case-insensitive + whitespace-tolerant")
    func caseInsensitiveAndTrimmed() {
        let lower = SampleFrameworkAvailability.versions(for: "swiftui")
        let upper = SampleFrameworkAvailability.versions(for: "SWIFTUI")
        let mixed = SampleFrameworkAvailability.versions(for: "SwiftUI")
        let padded = SampleFrameworkAvailability.versions(for: "  SwiftUI  ")
        #expect(lower.versions == upper.versions)
        #expect(upper.versions == mixed.versions)
        #expect(mixed.versions == padded.versions)
        #expect(lower.isExact && upper.isExact && mixed.isExact && padded.isExact)
    }

    @Test("frameworkFromProjectId extracts kebab-case prefix")
    func projectIdPrefixExtraction() {
        #expect(SampleFrameworkAvailability.frameworkFromProjectId(
            "swiftui-adopting-drag-and-drop"
        ) == "swiftui")
        #expect(SampleFrameworkAvailability.frameworkFromProjectId(
            "appintents-acceleratingappinteractionswithappintents"
        ) == "appintents")
        #expect(SampleFrameworkAvailability.frameworkFromProjectId(
            "mapkit-mkmapview-optimizing-something"
        ) == "mapkit")
    }

    @Test("frameworkFromProjectId returns nil for non-kebab id")
    func projectIdNonKebab() {
        #expect(SampleFrameworkAvailability.frameworkFromProjectId("SlothCreator") == nil)
        #expect(SampleFrameworkAvailability.frameworkFromProjectId("") == nil)
    }

    @Test("Table covers the 55+ corpus frameworks; no all-nil entry")
    func tableIntegrity() {
        // Every entry has at least one non-nil platform — the
        // schema permits all-nil but the consumer treats that as
        // "stamp nothing", so an all-nil entry would silently
        // regress the bug this PR fixes.
        for (slug, vers) in SampleFrameworkAvailability.table {
            let hasAny = vers.iOS != nil
                || vers.macOS != nil
                || vers.tvOS != nil
                || vers.watchOS != nil
                || vers.visionOS != nil
            #expect(hasAny, "Table entry '\(slug)' has all platforms nil — would silently regress #1104.")
        }
        #expect(SampleFrameworkAvailability.table.count >= 100)
    }
}
