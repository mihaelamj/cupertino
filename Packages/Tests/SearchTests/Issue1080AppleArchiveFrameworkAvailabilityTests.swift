@testable import AppleArchiveSource
import Foundation
import SearchModels
import Testing

// MARK: - #1080 — apple-archive static framework availability

//
// Pins the per-framework availability table that supplies
// platform-version overrides for the 14 frameworks in the
// apple-archive corpus. Pre-#1080 the strategy's per-DB
// `getFrameworkAvailability` lookup was self-referential for
// apple-archive (returns .empty until a row has min_ios populated,
// which never happens) — every archive row landed with all-NULL
// platforms. Post-fix the static table seeds the lookup.

@Suite("#1080 — apple-archive framework availability")
struct Issue1080AppleArchiveFrameworkAvailabilityTests {
    @Test("Foundation: universal across all 5 platforms")
    func foundation() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "Foundation")
        #expect(availability?.minIOS == "2.0")
        #expect(availability?.minMacOS == "10.0")
        #expect(availability?.minTvOS == "9.0")
        #expect(availability?.minWatchOS == "2.0")
        #expect(availability?.minVisionOS == "1.0")
    }

    @Test("UIKit: iOS+macOS(Catalyst)+tvOS+visionOS, no watchOS")
    func uikit() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "UIKit")
        #expect(availability?.minIOS == "2.0")
        #expect(availability?.minMacOS == "13.0")
        #expect(availability?.minTvOS == "9.0")
        #expect(availability?.minWatchOS == nil)
        #expect(availability?.minVisionOS == "1.0")
    }

    @Test("AppKit: macOS only, no iOS/tvOS/watchOS/visionOS")
    func appkit() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "AppKit")
        #expect(availability?.minIOS == nil)
        #expect(availability?.minMacOS == "10.0")
        #expect(availability?.minTvOS == nil)
        #expect(availability?.minWatchOS == nil)
        #expect(availability?.minVisionOS == nil)
    }

    @Test("Cocoa: macOS only (iOS counterpart is Cocoa Touch / UIKit)")
    func cocoa() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "Cocoa")
        #expect(availability?.minIOS == nil)
        #expect(availability?.minMacOS == "10.0")
    }

    @Test("CoreData: iOS 3.0, macOS 10.4 (Tiger introduction)")
    func coreData() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "CoreData")
        #expect(availability?.minIOS == "3.0")
        #expect(availability?.minMacOS == "10.4")
    }

    @Test("Comma-joined `CoreGraphics, Quartz2D` framework name resolves to one entry")
    func commaJoinedKey() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "CoreGraphics, Quartz2D")
        #expect(availability?.minIOS == "2.0")
        #expect(availability?.minMacOS == "10.0")
    }

    @Test("Bare `CoreGraphics` (without the Quartz2D suffix) also resolves")
    func bareCoreGraphics() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "CoreGraphics")
        #expect(availability?.minIOS == "2.0")
    }

    @Test("Case-insensitive fallback works for slightly off corpus rows")
    func caseInsensitiveFallback() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "foundation")
        #expect(availability?.minIOS == "2.0")
    }

    @Test("Trailing whitespace is tolerated")
    func trimmedKey() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "  Foundation  ")
        #expect(availability?.minIOS == "2.0")
    }

    @Test("Unknown framework returns nil (strategy falls back to per-DB lookup)")
    func unknownReturnsNil() {
        let availability = AppleArchiveFrameworkAvailability.availability(for: "TotallyMadeUpFramework")
        #expect(availability == nil)
    }

    @Test("Table covers exactly the 14 framework names that appear in the live archive corpus")
    func tableShape() {
        let expected: Set = [
            "Foundation", "UIKit", "Objective-C", "CoreData",
            "CoreGraphics, Quartz2D", "CoreGraphics",
            "QuartzCore, CoreAnimation", "QuartzCore", "CoreAnimation",
            "Cocoa", "CoreAudio", "Security", "CoreImage",
            "AppKit", "CoreFoundation", "Performance", "CoreText",
        ]
        #expect(Set(AppleArchiveFrameworkAvailability.table.keys) == expected)
    }
}
