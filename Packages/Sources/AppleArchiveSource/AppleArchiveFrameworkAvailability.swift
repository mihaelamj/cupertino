import Foundation
import SearchModels

// MARK: - Static framework-availability lookup for apple-archive

//
// #1080: apple-archive's legacy programming guides don't carry
// per-page availability metadata in the corpus, so the strategy's
// `index.getFrameworkAvailability(framework:)` query (which expects
// a previously-indexed sibling row with `min_ios IS NOT NULL`)
// always returns `.empty` for apple-archive.db. Pre-#1080 every
// archive row landed with all-NULL platforms, making
// `cupertino search --source apple-archive --min-macos 10` return
// zero rows regardless of content.
//
// Post-fix: this static table supplies per-framework introduction
// versions for the 14 frameworks in the archive corpus (Foundation,
// UIKit, CoreData, etc.). The strategy queries this table first; if
// no entry matches, it falls back to the per-DB lookup (which keeps
// working in case a future source seeds framework_availability).
//
// Versions are CONSERVATIVE FLOORS — the earliest platform release
// the framework appeared on. Apple's archive content is historical
// (pre-deprecation) so these are accurate baselines, not maximums.
// AppKit + Cocoa + Carbon-era frameworks are macOS-only (iOS NULL).
//
// Single source of truth: this table is the only place apple-archive
// frameworks get availability stamped. Adding a new framework to the
// archive corpus requires one entry here.
public enum AppleArchiveFrameworkAvailability {
    /// Lookup keyed by the literal `framework:` value from the
    /// archive .md frontmatter. The archive corpus has some
    /// comma-joined entries (e.g. "CoreGraphics, Quartz2D" —
    /// Quartz2D is the C-level drawing API inside CoreGraphics; they
    /// ship in lockstep) which are preserved verbatim here.
    public static let table: [String: Search.FrameworkAvailability] = [
        // Cocoa-era Foundation classes (NSString, NSArray,
        // NSNotification, etc.) — universal across Apple platforms.
        "Foundation": .init(minIOS: "2.0", minMacOS: "10.0", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // UIKit shipped with iPhone OS 2.0 SDK in 2008; macOS via
        // Mac Catalyst in 13.0 (2019); not on watchOS (SwiftUI on
        // watchOS uses WatchKit). visionOS adopted UIKit in 1.0.
        "UIKit": .init(minIOS: "2.0", minMacOS: "13.0", minTvOS: "9.0", minWatchOS: nil, minVisionOS: "1.0"),

        // Objective-C runtime — universal availability since the
        // earliest release of every Apple platform.
        "Objective-C": .init(minIOS: "2.0", minMacOS: "10.0", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // Core Data shipped with Mac OS X 10.4 Tiger (2005), iOS 3.0
        // (2009). Available on every platform since the platform
        // introduced an SDK.
        "CoreData": .init(minIOS: "3.0", minMacOS: "10.4", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // CoreGraphics + its Quartz2D drawing API ship together
        // since Mac OS X 10.0 and iPhoneOS 2.0.
        "CoreGraphics, Quartz2D": .init(
            minIOS: "2.0", minMacOS: "10.0", minTvOS: "9.0",
            minWatchOS: "2.0", minVisionOS: "1.0"
        ),
        "CoreGraphics": .init(minIOS: "2.0", minMacOS: "10.0", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // QuartzCore + Core Animation ship together since Mac OS X
        // 10.5 Leopard (2007), iPhone OS 2.0.
        "QuartzCore, CoreAnimation": .init(
            minIOS: "2.0", minMacOS: "10.5", minTvOS: "9.0",
            minWatchOS: "2.0", minVisionOS: "1.0"
        ),
        "QuartzCore": .init(minIOS: "2.0", minMacOS: "10.5", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),
        "CoreAnimation": .init(minIOS: "2.0", minMacOS: "10.5", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // Cocoa is the macOS-only umbrella (Foundation + AppKit).
        // Its iOS counterpart is Cocoa Touch (= Foundation + UIKit),
        // documented separately. Stamp macOS only.
        "Cocoa": .init(minIOS: nil, minMacOS: "10.0", minTvOS: nil, minWatchOS: nil, minVisionOS: nil),

        // Core Audio C-level APIs — universal since each platform's
        // first release.
        "CoreAudio": .init(minIOS: "2.0", minMacOS: "10.0", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // Security framework — keychain, certificates, crypto. Mac
        // OS X 10.2 (2002), iPhone OS 2.0.
        "Security": .init(minIOS: "2.0", minMacOS: "10.2", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // Core Image — image processing. Mac OS X 10.4 (2005), iOS
        // 5.0 (2011); arrived on watchOS later (5.0, 2018).
        "CoreImage": .init(minIOS: "5.0", minMacOS: "10.4", minTvOS: "9.0", minWatchOS: "5.0", minVisionOS: "1.0"),

        // AppKit is the macOS-only UI framework (the Mac counterpart
        // to UIKit). Stamp macOS only.
        "AppKit": .init(minIOS: nil, minMacOS: "10.0", minTvOS: nil, minWatchOS: nil, minVisionOS: nil),

        // Core Foundation C-level types (CFString, CFArray, etc.) —
        // toll-free bridged with Foundation; universal.
        "CoreFoundation": .init(minIOS: "2.0", minMacOS: "10.0", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // "Performance" is an archive-content category (memory
        // management, profiling, instrumentation guides), not a real
        // framework. Apply the cross-platform Foundation baseline.
        "Performance": .init(minIOS: "2.0", minMacOS: "10.0", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),

        // Core Text shipped on Mac OS X 10.5 (2007), iOS 3.2 (2010).
        "CoreText": .init(minIOS: "3.2", minMacOS: "10.5", minTvOS: "9.0", minWatchOS: "2.0", minVisionOS: "1.0"),
    ]

    /// Lookup with case-insensitive fallback so a corpus row with
    /// "core data" or "CoreData " (trailing space) still matches.
    /// Returns nil when the framework is unknown — the strategy then
    /// falls back to the per-DB lookup (no-op for apple-archive,
    /// useful if a future source seeds availability into archive.db).
    public static func availability(for framework: String) -> Search.FrameworkAvailability? {
        let trimmed = framework.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = table[trimmed] { return exact }
        let lower = trimmed.lowercased()
        for (key, value) in table where key.lowercased() == lower {
            return value
        }
        return nil
    }
}
