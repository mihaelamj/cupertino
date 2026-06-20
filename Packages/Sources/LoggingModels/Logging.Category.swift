import Foundation

// MARK: - Logging.Category

extension Logging {
    /// Subsystem category carried alongside every log record. Each
    /// concrete `Logging.Recording` decides what to do with the category
    /// (Apple OSLog uses it for `os.Logger(subsystem:category:)`; a
    /// console-only test stub may stringify it as a tag).
    ///
    /// Post-#1042 Cluster 10 this is a rawValue-String struct, not a
    /// closed enum: adding a new per-source category (when WWDC
    /// transcripts or another source joins and wants its own OSLog
    /// channel) is a `static let` declaration, with no exhaustive
    /// switch arm to update in `Logging.LiveRecording.mapCategory` or
    /// `Logging.Unified`.
    public struct Category: RawRepresentable, Sendable, Equatable, Hashable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let crawler = Category(rawValue: "crawler")
        public static let mcp = Category(rawValue: "mcp")
        public static let search = Category(rawValue: "search")
        public static let cli = Category(rawValue: "cli")
        public static let evolution = Category(rawValue: "evolution")
        public static let samples = Category(rawValue: "samples")
        public static let packages = Category(rawValue: "packages")
        public static let archive = Category(rawValue: "archive")
        public static let hig = Category(rawValue: "hig")

        /// The 9 production categories. Test stubs + LoggingModels'
        /// own canonical-cases test iterate this list; new sources can
        /// register categories outside the list and they route through
        /// `LiveRecording.mapCategory`'s dict-based dispatch via raw
        /// values.
        public static let allKnownCases: [Category] = [
            .crawler, .mcp, .search, .cli,
            .evolution, .samples, .packages, .archive, .hig,
        ]

        /// Back-compat alias for code paths that previously used the
        /// closed enum's `CaseIterable` conformance. Aliased to
        /// `allKnownCases` post-#1042 Cluster 10.
        public static let allCases: [Category] = allKnownCases
    }
}
