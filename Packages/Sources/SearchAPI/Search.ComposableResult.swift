import Foundation
import SearchModels
import SharedConstants

/// Sample.Search (in SharedConstants) shadows the Search SPM target inside any
/// extension Sample {} scope. Pin the SPM target so Sample.Atom.source can still
/// reach SearchModule.Source via SearchModule.Source.
public typealias SearchModule = Search

// MARK: - Composable Search Result (LEGO Model)

//
// Design Philosophy:
// Each component is a discrete, self-contained unit that can be:
// 1. Rendered independently
// 2. Composed with other sections
// 3. Filtered, sorted, or transformed
// 4. Serialized to any format (Markdown, JSON, HTML)
//
// Hierarchy:
// - ResultAtom: Single item (one doc, one sample, one proposal)
// - ResultSection: Collection of atoms with metadata (one source)
// - ComposedResult: Full response with multiple sections + hints/tips
//

// MARK: - Source Identity

// `Search.Source` lifted to `SearchModels/Search.DomainTypes.swift` by
// the #898F follow-up. ComposableResult still uses `SearchModule.Source`
// (the `Search` namespace alias declared at the top of this file) and
// `Search.SourceRegistry` (in `SearchModels`).

// MARK: - Result Atom (Single Item)

/// Protocol for any single search result item
extension Search {
    public protocol ResultAtom: Sendable, Identifiable {
        var source: SearchModule.Source { get }
        var title: String { get }
        var summary: String { get }
        var uri: String { get }
        var score: Double { get }
    }
}

/// Documentation result atom (Apple Docs, HIG, Archive, Swift Evolution, etc.)
extension Search {
    public struct DocAtom: ResultAtom, Codable, Sendable {
        public let id: UUID
        public let source: SearchModule.Source
        public let title: String
        public let summary: String
        public let uri: String
        public let score: Double
        public let framework: String?
        public let availability: [Search.PlatformAvailability]?

        public init(
            id: UUID = UUID(),
            source: SearchModule.Source,
            title: String,
            summary: String,
            uri: String,
            score: Double,
            framework: String? = nil,
            availability: [Search.PlatformAvailability]? = nil
        ) {
            self.id = id
            self.source = source
            self.title = title
            self.summary = summary
            self.uri = uri
            self.score = score
            self.framework = framework
            self.availability = availability
        }

        /// Convert from existing Search.Result
        public init(from result: Search.Result, source: SearchModule.Source) {
            id = result.id
            self.source = source
            title = result.title
            summary = result.cleanedSummary
            uri = result.uri
            score = result.score
            framework = result.framework.isEmpty ? nil : result.framework
            availability = result.availability
        }

        /// Availability as compact string
        public var availabilityString: String? {
            guard let availability, !availability.isEmpty else { return nil }
            return availability
                .filter { !$0.unavailable }
                .compactMap { platform -> String? in
                    guard let version = platform.introducedAt else { return nil }
                    var str = "\(platform.name) \(version)+"
                    if platform.deprecated { str += " (deprecated)" }
                    if platform.beta { str += " (beta)" }
                    return str
                }
                .joined(separator: ", ")
        }
    }
}

/// Sample code result atom
extension Sample {
    public struct Atom: SearchModule.ResultAtom, Codable, Sendable {
        public let id: UUID
        public let source: SearchModule.Source
        public let title: String
        public let summary: String
        public let uri: String
        public let score: Double
        public let frameworks: [String]
        public let downloadURL: String?
        public let hasLocalCopy: Bool

        public init(
            id: UUID = UUID(),
            title: String,
            summary: String,
            uri: String,
            score: Double,
            frameworks: [String] = [],
            downloadURL: String? = nil,
            hasLocalCopy: Bool = false
        ) {
            self.id = id
            source = .samples
            self.title = title
            self.summary = summary
            self.uri = uri
            self.score = score
            self.frameworks = frameworks
            self.downloadURL = downloadURL
            self.hasLocalCopy = hasLocalCopy
        }
    }
}

/// Swift package result atom
extension Search {
    public struct PackageAtom: ResultAtom, Codable, Sendable {
        public let id: UUID
        public let source: SearchModule.Source
        public let title: String
        public let summary: String
        public let uri: String
        public let score: Double
        public let owner: String
        public let stars: Int
        public let isAppleOfficial: Bool
        public let documentationURL: String?

        public init(
            id: UUID = UUID(),
            title: String,
            summary: String,
            uri: String,
            score: Double,
            owner: String,
            stars: Int,
            isAppleOfficial: Bool = false,
            documentationURL: String? = nil
        ) {
            self.id = id
            source = .packages
            self.title = title
            self.summary = summary
            self.uri = uri
            self.score = score
            self.owner = owner
            self.stars = stars
            self.isAppleOfficial = isAppleOfficial
            self.documentationURL = documentationURL
        }
    }
}

// MARK: - Result Section (Collection from One Source)

/// A section containing results from a single source
extension Search {
    public struct ResultSection<Atom: ResultAtom>: Sendable {
        public let source: SearchModule.Source
        public let atoms: [Atom]
        public let totalAvailable: Int // Total in source (may exceed atoms.count due to limits)

        public init(source: SearchModule.Source, atoms: [Atom], totalAvailable: Int? = nil) {
            self.source = source
            self.atoms = atoms
            self.totalAvailable = totalAvailable ?? atoms.count
        }

        public var isEmpty: Bool {
            atoms.isEmpty
        }

        public var count: Int {
            atoms.count
        }

        public var hasMore: Bool {
            totalAvailable > atoms.count
        }
    }
}

// MARK: - Hint & Tip Types

/// A hint about additional results in other sources
extension Search {
    public struct SourceHint: Codable, Sendable {
        public let source: SearchModule.Source
        public let count: Int
        public let topTitles: [String] // Preview of what's available
        public let howToAccess: String // e.g., "Use source: samples"

        public init(source: SearchModule.Source, count: Int, topTitles: [String], howToAccess: String) {
            self.source = source
            self.count = count
            self.topTitles = topTitles
            self.howToAccess = howToAccess
        }
    }
}

/// A contextual tip for the user/AI
extension Search {
    public struct Tip: Codable, Sendable, Identifiable {
        public let id: UUID
        public let category: TipCategory
        public let message: String
        public let actionHint: String? // Optional action to take

        public enum TipCategory: String, Codable, Sendable {
            case refinement // Narrow/broaden search
            case source // Try different source
            case availability // Platform-specific tip
            case bestPractice // Coding/design pattern tip
            case related // Related topic suggestion
        }

        public init(
            id: UUID = UUID(),
            category: TipCategory,
            message: String,
            actionHint: String? = nil
        ) {
            self.id = id
            self.category = category
            self.message = message
            self.actionHint = actionHint
        }
    }
}

/// Quick link to a relevant resource
extension Search {
    public struct QuickLink: Codable, Sendable, Identifiable {
        public let id: UUID
        public let label: String
        public let uri: String
        public let description: String?

        public init(id: UUID = UUID(), label: String, uri: String, description: String? = nil) {
            self.id = id
            self.label = label
            self.uri = uri
            self.description = description
        }
    }
}

// MARK: - Composed Result (Full Response)

/// Complete search response assembled from sections
/// This is the "organism" - the fully assembled LEGO model
extension Search {
    public struct ComposedSearchResult: Sendable {
        public let query: String
        public let framework: String?
        public let timestamp: Date

        /// Primary results (what user asked for)
        public let primarySection: ResultSection<DocAtom>?

        // Supporting sections (related sources)
        public let sampleSection: ResultSection<Sample.Atom>?
        public let higSection: ResultSection<DocAtom>?
        public let evolutionSection: ResultSection<DocAtom>?
        public let archiveSection: ResultSection<DocAtom>?
        public let swiftOrgSection: ResultSection<DocAtom>?
        public let swiftBookSection: ResultSection<DocAtom>?
        public let packageSection: ResultSection<PackageAtom>?

        /// Hints about other sources (teasers)
        public let hints: [SourceHint]

        /// Contextual tips
        public let tips: [Search.Tip]

        /// Quick links
        public let quickLinks: [QuickLink]

        public init(
            query: String,
            framework: String? = nil,
            timestamp: Date = Date(),
            primarySection: ResultSection<DocAtom>? = nil,
            sampleSection: ResultSection<Sample.Atom>? = nil,
            higSection: ResultSection<DocAtom>? = nil,
            evolutionSection: ResultSection<DocAtom>? = nil,
            archiveSection: ResultSection<DocAtom>? = nil,
            swiftOrgSection: ResultSection<DocAtom>? = nil,
            swiftBookSection: ResultSection<DocAtom>? = nil,
            packageSection: ResultSection<PackageAtom>? = nil,
            hints: [SourceHint] = [],
            tips: [Search.Tip] = [],
            quickLinks: [QuickLink] = []
        ) {
            self.query = query
            self.framework = framework
            self.timestamp = timestamp
            self.primarySection = primarySection
            self.sampleSection = sampleSection
            self.higSection = higSection
            self.evolutionSection = evolutionSection
            self.archiveSection = archiveSection
            self.swiftOrgSection = swiftOrgSection
            self.swiftBookSection = swiftBookSection
            self.packageSection = packageSection
            self.hints = hints
            self.tips = tips
            self.quickLinks = quickLinks
        }

        /// Total results across all sections
        public var totalResults: Int {
            var total = 0
            total += primarySection?.count ?? 0
            total += sampleSection?.count ?? 0
            total += higSection?.count ?? 0
            total += evolutionSection?.count ?? 0
            total += archiveSection?.count ?? 0
            total += swiftOrgSection?.count ?? 0
            total += swiftBookSection?.count ?? 0
            total += packageSection?.count ?? 0
            return total
        }

        /// All non-empty sections for iteration
        public var allSections: [SearchModule.Source] {
            var sources: [SearchModule.Source] = []
            if let section = primarySection, !section.isEmpty { sources.append(section.source) }
            if let section = sampleSection, !section.isEmpty { sources.append(section.source) }
            if let section = higSection, !section.isEmpty { sources.append(section.source) }
            if let section = evolutionSection, !section.isEmpty { sources.append(section.source) }
            if let section = archiveSection, !section.isEmpty { sources.append(section.source) }
            if let section = swiftOrgSection, !section.isEmpty { sources.append(section.source) }
            if let section = swiftBookSection, !section.isEmpty { sources.append(section.source) }
            if let section = packageSection, !section.isEmpty { sources.append(section.source) }
            return sources
        }
    }
}

// MARK: - Builder (Fluent API for Composition)

/// Builder for assembling ComposedSearchResult piece by piece
extension Search {
    // @unchecked Sendable per concurrency.md §24: builder pattern;
    // the class accumulates mutable per-source result lists during
    // assembly. Builders are single-threaded by convention (each
    // caller constructs + finalises its own builder); @unchecked
    // acknowledges the convention without converting to an actor
    // (which would force the builder API to be async).

    public final class ComposedResultBuilder: @unchecked Sendable {
        private var query: String = ""
        private var framework: String?
        private var primarySection: ResultSection<DocAtom>?
        private var sampleSection: ResultSection<Sample.Atom>?
        private var higSection: ResultSection<DocAtom>?
        private var evolutionSection: ResultSection<DocAtom>?
        private var archiveSection: ResultSection<DocAtom>?
        private var swiftOrgSection: ResultSection<DocAtom>?
        private var swiftBookSection: ResultSection<DocAtom>?
        private var packageSection: ResultSection<PackageAtom>?
        private var hints: [SourceHint] = []
        private var tips: [Search.Tip] = []
        private var quickLinks: [QuickLink] = []

        public init() {}

        @discardableResult
        public func query(_ query: String) -> Self {
            self.query = query
            return self
        }

        @discardableResult
        public func framework(_ framework: String?) -> Self {
            self.framework = framework
            return self
        }

        @discardableResult
        public func primary(_ section: ResultSection<DocAtom>) -> Self {
            primarySection = section
            return self
        }

        @discardableResult
        public func samples(_ section: ResultSection<Sample.Atom>) -> Self {
            sampleSection = section
            return self
        }

        @discardableResult
        public func hig(_ section: ResultSection<DocAtom>) -> Self {
            higSection = section
            return self
        }

        @discardableResult
        public func evolution(_ section: ResultSection<DocAtom>) -> Self {
            evolutionSection = section
            return self
        }

        @discardableResult
        public func archive(_ section: ResultSection<DocAtom>) -> Self {
            archiveSection = section
            return self
        }

        @discardableResult
        public func swiftOrg(_ section: ResultSection<DocAtom>) -> Self {
            swiftOrgSection = section
            return self
        }

        @discardableResult
        public func swiftBook(_ section: ResultSection<DocAtom>) -> Self {
            swiftBookSection = section
            return self
        }

        @discardableResult
        public func packages(_ section: ResultSection<PackageAtom>) -> Self {
            packageSection = section
            return self
        }

        @discardableResult
        public func addHint(_ hint: SourceHint) -> Self {
            hints.append(hint)
            return self
        }

        @discardableResult
        public func addTip(_ tip: Search.Tip) -> Self {
            tips.append(tip)
            return self
        }

        @discardableResult
        public func addQuickLink(_ link: QuickLink) -> Self {
            quickLinks.append(link)
            return self
        }

        public func build() -> ComposedSearchResult {
            ComposedSearchResult(
                query: query,
                framework: framework,
                primarySection: primarySection,
                sampleSection: sampleSection,
                higSection: higSection,
                evolutionSection: evolutionSection,
                archiveSection: archiveSection,
                swiftOrgSection: swiftOrgSection,
                swiftBookSection: swiftBookSection,
                packageSection: packageSection,
                hints: hints,
                tips: tips,
                quickLinks: quickLinks
            )
        }
    }
}

// MARK: - Query Intent (For Source Prioritization)

// `Search.QueryIntent` + `detectQueryIntent(_:)` lifted to
// `SearchModels/Search.DomainTypes.swift` by the #898F follow-up.

// MARK: - Source Properties (Quarks - Measurable Attributes)

// `Search.SourceProperties` lifted to
// `SearchModels/Search.DomainTypes.swift` by the #898F follow-up.

// MARK: - Unified Search Summary

/// Short summary of results from all sources (for "search all")
extension Search {
    public struct UnifiedSearchSummary: Codable, Sendable {
        public let query: String
        public let totalResults: Int
        public let sourceSummaries: [SourceSummary]
        public let hints: [SourceHint]
        public let tips: [Search.Tip]
        public let detectedIntent: QueryIntent

        public init(
            query: String,
            totalResults: Int,
            sourceSummaries: [SourceSummary],
            hints: [SourceHint] = [],
            tips: [Search.Tip] = [],
            detectedIntent: QueryIntent = .apiReference
        ) {
            self.query = query
            self.totalResults = totalResults
            self.sourceSummaries = sourceSummaries
            self.hints = hints
            self.tips = tips
            self.detectedIntent = detectedIntent
        }

        /// Short summary for one source in unified results
        public struct SourceSummary: Codable, Sendable {
            public let source: SearchModule.Source
            public let count: Int
            public let topResult: TopResultPreview?
            public let hasMore: Bool

            public init(source: SearchModule.Source, count: Int, topResult: TopResultPreview?, hasMore: Bool) {
                self.source = source
                self.count = count
                self.topResult = topResult
                self.hasMore = hasMore
            }
        }

        /// Preview of top result for summary display
        public struct TopResultPreview: Codable, Sendable {
            public let title: String
            public let briefSummary: String // First ~100 chars
            public let uri: String

            public init(title: String, briefSummary: String, uri: String) {
                self.title = title
                self.briefSummary = briefSummary
                self.uri = uri
            }
        }
    }
}

// MARK: - Tip Factory (Common Tips)

/// Factory for creating common search tips
extension Search {
    public enum TipFactory {
        public static func noResultsTip(query: String) -> Search.Tip {
            Search.Tip(
                category: .refinement,
                message: "No results for '\(query)'. Try broader terms or check spelling.",
                actionHint: "Remove specific version numbers or use related framework names"
            )
        }

        // #934 Step 3b: `tryOtherSourceTip(current:suggested:)` deleted.
        // It read `suggested.displayName` which reached for the static
        // `Search.SourceRegistry`. The factory had zero callers in the
        // production tree at deletion time. If a future caller wants
        // this tip, take a `Search.SourceLookup` as a third parameter
        // and route the display name through `lookup.displayName(for:)`.

        public static func availabilityTip(platform: String, minVersion: String) -> Search.Tip {
            Search.Tip(
                category: .availability,
                message: "This API requires \(platform) \(minVersion)+",
                actionHint: "Check availability before using in production"
            )
        }

        public static func deprecationTip(replacement: String?) -> Search.Tip {
            Search.Tip(
                category: .bestPractice,
                message: "This API is deprecated." + (replacement.map { " Use \($0) instead." } ?? ""),
                actionHint: replacement.map { "Search for \($0)" }
            )
        }

        public static func swiftEvolutionTip(proposalID: String) -> Search.Tip {
            Search.Tip(
                category: .related,
                message: "See Swift Evolution proposal \(proposalID) for background",
                actionHint: "Use source: swift-evolution for full proposal"
            )
        }

        public static func sampleCodeAvailableTip(count: Int) -> Search.Tip {
            Search.Tip(
                category: .source,
                message: "\(count) sample project\(count == 1 ? "" : "s") available with working code",
                actionHint: "Use source: samples to explore"
            )
        }

        public static func designGuidelineTip() -> Search.Tip {
            Search.Tip(
                category: .source,
                message: "Check Human Interface Guidelines for design best practices",
                actionHint: "Use source: hig"
            )
        }
    }
}
