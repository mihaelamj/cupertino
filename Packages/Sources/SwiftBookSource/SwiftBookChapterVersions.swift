import Foundation
import SearchModels
import SharedConstants

// MARK: - Per-chapter Swift-version platform inference

//
// #1095: every swift-book row was stamped with the universal Swift
// baseline (iOS 8.0 / macOS 10.9 / tvOS 9.0 / watchOS 2.0 /
// visionOS 1.0) — correct for most chapters but wrong for chapters
// covering Swift features introduced after Swift 1.0. The
// concurrency chapter requires Swift 5.5 (iOS 13.0+); macros
// require Swift 5.9 (iOS 17.0+).
//
// This table maps the canonical chapter slug (URL last-path-
// component, lowercased) to the platform-version floor. The strategy
// looks up each indexed page's slug and stamps the right values.
//
// Slugs not in the table inherit the universal baseline. The Swift
// → platform-version mapping is the official "Swift X.Y first
// shipped on" matrix:
//
//   Swift 5.5  →  iOS 13.0 / macOS 12.0 / tvOS 15.0 / watchOS 8.0  / visionOS 1.0
//   Swift 5.7  →  iOS 16.0 / macOS 13.0 / tvOS 16.0 / watchOS 9.0  / visionOS 1.0
//   Swift 5.9  →  iOS 17.0 / macOS 14.0 / tvOS 17.0 / watchOS 10.0 / visionOS 1.0
//   Swift 6.0  →  iOS 18.0 / macOS 15.0 / tvOS 18.0 / watchOS 11.0 / visionOS 2.0
//
// The visionOS column is uniformly 1.0 until Swift 6.0 (visionOS
// 1.0 shipped with Xcode 15 / Swift 5.9; explicit floor only matters
// for Swift 6.0+ where it bumps to 2.0).

public enum SwiftBookChapterVersions {
    public struct ChapterFloor: Sendable, Equatable {
        public let iOS: String?
        public let macOS: String?
        public let tvOS: String?
        public let watchOS: String?
        public let visionOS: String?

        public init(iOS: String?, macOS: String?, tvOS: String?, watchOS: String?, visionOS: String?) {
            self.iOS = iOS
            self.macOS = macOS
            self.tvOS = tvOS
            self.watchOS = watchOS
            self.visionOS = visionOS
        }

        /// Default Swift baseline — Swift 1.0 / 2.0 era. Used for
        /// chapters not in the per-chapter override table.
        public static let universalSwiftBaseline = ChapterFloor(
            iOS: "8.0", macOS: "10.9", tvOS: "9.0", watchOS: "2.0", visionOS: "1.0"
        )

        /// Swift 5.5 (concurrency).
        public static let swift55 = ChapterFloor(
            iOS: "13.0", macOS: "12.0", tvOS: "15.0", watchOS: "8.0", visionOS: "1.0"
        )

        /// Swift 5.9 (macros, parameter packs).
        public static let swift59 = ChapterFloor(
            iOS: "17.0", macOS: "14.0", tvOS: "17.0", watchOS: "10.0", visionOS: "1.0"
        )
    }

    /// Slug → per-chapter floor. Keys are canonical URL last-path-
    /// components (lowercased), matching the URI shape `swift-book://<slug>`
    /// post-#1084. Chapters not listed inherit `.universalSwiftBaseline`.
    public static let table: [String: ChapterFloor] = [
        // Swift 5.5: structured concurrency (async/await, Tasks,
        // actors). The Swift Book has 3 concurrency-related
        // chapters that all carry the same Swift 5.5 floor.
        "concurrency": .swift55,
        "structuredconcurrency": .swift55,
        "actors": .swift55,

        // Swift 5.9: macros + parameter packs.
        "macros": .swift59,
    ]

    /// Lookup with normalization. Returns the per-chapter floor if
    /// the slug is in the table, else `.universalSwiftBaseline`.
    public static func floor(forSlug slug: String) -> ChapterFloor {
        table[slug.lowercased()] ?? .universalSwiftBaseline
    }
}
