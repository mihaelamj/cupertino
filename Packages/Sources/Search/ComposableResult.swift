import Foundation

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

/// Identifies which documentation source produced a result
public enum SearchSource: String, Codable, Sendable, CaseIterable {
    case appleDocs = "apple-docs"
    case samples
    case hig
    case appleArchive = "apple-archive"
    case swiftEvolution = "swift-evolution"
    case swiftOrg = "swift-org"
    case swiftBook = "swift-book"
    case packages

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .appleDocs: return "Apple Documentation"
        case .samples: return "Sample Code"
        case .hig: return "Human Interface Guidelines"
        case .appleArchive: return "Apple Archive (Legacy)"
        case .swiftEvolution: return "Swift Evolution"
        case .swiftOrg: return "Swift.org"
        case .swiftBook: return "The Swift Programming Language"
        case .packages: return "Swift Packages"
        }
    }

    /// Emoji prefix for display
    public var emoji: String {
        switch self {
        case .appleDocs: return "📘"
        case .samples: return "💻"
        case .hig: return "🎨"
        case .appleArchive: return "📚"
        case .swiftEvolution: return "🔮"
        case .swiftOrg: return "🦅"
        case .swiftBook: return "📖"
        case .packages: return "📦"
        }
    }
}

// MARK: - Result Atom (Single Item)

/// Protocol for any single search result item
public protocol ResultAtom: Sendable, Identifiable {
    var source: SearchSource { get }
    var title: String { get }
    var summary: String { get }
    var uri: String { get }
    var score: Double { get }
}

/// Documentation result atom (Apple Docs, HIG, Archive, Swift Evolution, etc.)
public struct DocAtom: ResultAtom, Codable, Sendable {
    public let id: UUID
    public let source: SearchSource
    public let title: String
    public let summary: String
    public let uri: String
    public let score: Double
    public let framework: String?
    public let availability: [SearchPlatformAvailability]?

    public init(
        id: UUID = UUID(),
        source: SearchSource,
        title: String,
        summary: String,
        uri: String,
        score: Double,
        framework: String? = nil,
        availability: [SearchPlatformAvailability]? = nil
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
    public init(from result: Search.Result, source: SearchSource) {
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

/// Sample code result atom
public struct SampleAtom: ResultAtom, Codable, Sendable {
    public let id: UUID
    public let source: SearchSource
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

/// Swift package result atom
public struct PackageAtom: ResultAtom, Codable, Sendable {
    public let id: UUID
    public let source: SearchSource
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

// MARK: - Result Section (Collection from One Source)

/// A section containing results from a single source
public struct ResultSection<Atom: ResultAtom>: Sendable {
    public let source: SearchSource
    public let atoms: [Atom]
    public let totalAvailable: Int // Total in source (may exceed atoms.count due to limits)

    public init(source: SearchSource, atoms: [Atom], totalAvailable: Int? = nil) {
        self.source = source
        self.atoms = atoms
        self.totalAvailable = totalAvailable ?? atoms.count
    }

    public var isEmpty: Bool { atoms.isEmpty }
    public var count: Int { atoms.count }
    public var hasMore: Bool { totalAvailable > atoms.count }
}

// MARK: - Hint & Tip Types

/// A hint about additional results in other sources
public struct SourceHint: Codable, Sendable {
    public let source: SearchSource
    public let count: Int
    public let topTitles: [String] // Preview of what's available
    public let howToAccess: String // e.g., "Use source: samples"

    public init(source: SearchSource, count: Int, topTitles: [String], howToAccess: String) {
        self.source = source
        self.count = count
        self.topTitles = topTitles
        self.howToAccess = howToAccess
    }
}

/// A contextual tip for the user/AI
public struct SearchTip: Codable, Sendable, Identifiable {
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

/// Quick link to a relevant resource
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

// MARK: - Composed Result (Full Response)

/// Complete search response assembled from sections
/// This is the "organism" - the fully assembled LEGO model
public struct ComposedSearchResult: Sendable {
    public let query: String
    public let framework: String?
    public let timestamp: Date

    // Primary results (what user asked for)
    public let primarySection: ResultSection<DocAtom>?

    // Supporting sections (related sources)
    public let sampleSection: ResultSection<SampleAtom>?
    public let higSection: ResultSection<DocAtom>?
    public let evolutionSection: ResultSection<DocAtom>?
    public let archiveSection: ResultSection<DocAtom>?
    public let swiftOrgSection: ResultSection<DocAtom>?
    public let swiftBookSection: ResultSection<DocAtom>?
    public let packageSection: ResultSection<PackageAtom>?

    // Hints about other sources (teasers)
    public let hints: [SourceHint]

    // Contextual tips
    public let tips: [SearchTip]

    // Quick links
    public let quickLinks: [QuickLink]

    public init(
        query: String,
        framework: String? = nil,
        timestamp: Date = Date(),
        primarySection: ResultSection<DocAtom>? = nil,
        sampleSection: ResultSection<SampleAtom>? = nil,
        higSection: ResultSection<DocAtom>? = nil,
        evolutionSection: ResultSection<DocAtom>? = nil,
        archiveSection: ResultSection<DocAtom>? = nil,
        swiftOrgSection: ResultSection<DocAtom>? = nil,
        swiftBookSection: ResultSection<DocAtom>? = nil,
        packageSection: ResultSection<PackageAtom>? = nil,
        hints: [SourceHint] = [],
        tips: [SearchTip] = [],
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
    public var allSections: [SearchSource] {
        var sources: [SearchSource] = []
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

// MARK: - Builder (Fluent API for Composition)

/// Builder for assembling ComposedSearchResult piece by piece
public final class ComposedResultBuilder: @unchecked Sendable {
    private var query: String = ""
    private var framework: String?
    private var primarySection: ResultSection<DocAtom>?
    private var sampleSection: ResultSection<SampleAtom>?
    private var higSection: ResultSection<DocAtom>?
    private var evolutionSection: ResultSection<DocAtom>?
    private var archiveSection: ResultSection<DocAtom>?
    private var swiftOrgSection: ResultSection<DocAtom>?
    private var swiftBookSection: ResultSection<DocAtom>?
    private var packageSection: ResultSection<PackageAtom>?
    private var hints: [SourceHint] = []
    private var tips: [SearchTip] = []
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
    public func samples(_ section: ResultSection<SampleAtom>) -> Self {
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
    public func addTip(_ tip: SearchTip) -> Self {
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

// MARK: - Query Intent (For Source Prioritization)

/// Detected intent of the search query - determines which sources get boosted
/// This is learned empirically from analyzing each source's nature
public enum QueryIntent: String, Codable, Sendable {
    case apiReference // "UIView frame", "String methods" → apple-docs
    case howTo // "how to animate", "implement dark mode" → samples, apple-docs
    case designGuidance // "button placement", "typography best practices" → hig
    case languageFeature // "async/await", "property wrappers" → swift-evolution, swift-book
    case conceptual // "concurrency model", "memory management" → apple-docs, swift-book
    case troubleshooting // "crash when", "error handling" → samples, archive
    case migration // "migrate to SwiftUI", "deprecation" → archive, evolution
    case packageDiscovery // "networking library", "JSON parsing package" → packages
    case legacy // "Objective-C", "NSObject", older frameworks → archive, apple-docs

    /// Sources boosted for this intent (in priority order)
    public var boostedSources: [SearchSource] {
        switch self {
        case .apiReference:
            return [.appleDocs, .swiftBook]
        case .howTo:
            return [.samples, .appleDocs, .swiftOrg]
        case .designGuidance:
            return [.hig, .appleDocs]
        case .languageFeature:
            return [.swiftEvolution, .swiftBook, .swiftOrg]
        case .conceptual:
            return [.appleDocs, .swiftBook, .swiftOrg]
        case .troubleshooting:
            return [.samples, .appleArchive, .appleDocs]
        case .migration:
            return [.appleArchive, .swiftEvolution, .appleDocs]
        case .packageDiscovery:
            return [.packages, .swiftOrg]
        case .legacy:
            return [.appleArchive, .appleDocs] // Archive first for legacy content
        }
    }

    /// Boost multiplier for boosted sources (1.0 = no boost)
    public var boostMultiplier: Double {
        2.0 // Boosted sources get 2x score
    }
}

/// Analyze a query to detect intent
/// Uses keyword heuristics and pattern matching
public func detectQueryIntent(_ query: String) -> QueryIntent {
    let queryLower = query.lowercased()

    // Legacy/Objective-C detection (check early - specific patterns)
    // NS prefix is the classic Objective-C naming convention
    // Also detect explicit Objective-C mentions and older frameworks
    let legacyPrefixes = [
        "nsobject",
        "nsarray",
        "nsdictionary",
        "nsstring",
        "nsnumber",
        "nsurl",
        "nsdata",
        "nserror",
        "nsnotification",
        "nscoder",
        "nsview",
        "nswindow",
        "nsapplication",
        "nstableview",
        "uiview",
        "uiviewcontroller",
        "uitableview",
        "uicollectionview",
    ]
    let legacyKeywords = [
        "objective-c",
        "objc",
        "@objc",
        "bridging",
        "toll-free",
        "autorelease",
        "retain",
        "release",
        "arc",
        "manual memory",
        "nil vs null",
        "selector",
        "@selector",
        "respondsToSelector",
        "performSelector",
        "nib",
        "xib",
        "storyboard segue",
    ]
    let legacyFrameworks = [
        "carbon",
        "cocoa",
        "appkit legacy",
        "foundation legacy",
        "core foundation",
        "cfstring",
        "cfarray",
        "cfdictionary",
    ]

    if legacyKeywords.contains(where: { queryLower.contains($0) }) ||
        legacyFrameworks.contains(where: { queryLower.contains($0) }) {
        return .legacy
    }
    // Check for NS-prefixed classes (but not modern ones like NSObject in Swift context)
    if legacyPrefixes.contains(where: { queryLower.hasPrefix($0) }),
       !queryLower.contains("swift") {
        return .legacy
    }

    // How-to queries
    if queryLower.contains("how to") || queryLower.contains("implement") ||
        queryLower.contains("create") || queryLower.contains("tutorial") ||
        queryLower.contains("example") || queryLower.contains("sample") {
        return .howTo
    }

    // Design guidance
    if queryLower.contains("design") || queryLower.contains("guideline") ||
        queryLower.contains("best practice") || queryLower.contains("layout") ||
        queryLower.contains("typography") || queryLower.contains("ux") ||
        queryLower.contains("user interface") || queryLower.contains("accessibility design") {
        return .designGuidance
    }

    // Language features (Swift Evolution territory)
    if queryLower.contains("proposal") || queryLower.contains("se-") ||
        queryLower.contains("async") || queryLower.contains("await") ||
        queryLower.contains("actor") || queryLower.contains("sendable") ||
        queryLower.contains("property wrapper") || queryLower.contains("result builder") ||
        queryLower.contains("macro") || queryLower.contains("swift 5") ||
        queryLower.contains("swift 6") {
        return .languageFeature
    }

    // Migration (from old to new)
    if queryLower.contains("migrate") || queryLower.contains("deprecated") ||
        queryLower.contains("replacement") || queryLower.contains("upgrade") ||
        queryLower.contains("convert to swift") || queryLower.contains("swiftui from uikit") ||
        queryLower.contains("modernize") {
        return .migration
    }

    // Troubleshooting
    if queryLower.contains("error") || queryLower.contains("crash") ||
        queryLower.contains("fix") || queryLower.contains("debug") ||
        queryLower.contains("issue") || queryLower.contains("problem") ||
        queryLower.contains("not working") || queryLower.contains("fails") {
        return .troubleshooting
    }

    // Package discovery
    if queryLower.contains("library") || queryLower.contains("package") ||
        queryLower.contains("dependency") || queryLower.contains("spm") ||
        queryLower.contains("swift package") || queryLower.contains("cocoapods") {
        return .packageDiscovery
    }

    // Conceptual understanding
    if queryLower.contains("concept") || queryLower.contains("architecture") ||
        queryLower.contains("pattern") || queryLower.contains("how does") ||
        queryLower.contains("what is") || queryLower.contains("explain") ||
        queryLower.contains("understand") || queryLower.contains("overview") {
        return .conceptual
    }

    // Default to API reference
    return .apiReference
}

// MARK: - Source Properties (Quarks - Measurable Attributes)

/// Properties of each documentation source
/// These are the "quarks" - fundamental measurable attributes
/// Values determined empirically by testing each source
public struct SourceProperties: Codable, Sendable {
    /// How authoritative/official is this source? (0.0-1.0)
    public let authority: Double

    /// How current/fresh is the content? (0.0-1.0)
    public let freshness: Double

    /// How comprehensive is the coverage? (0.0-1.0)
    public let comprehensiveness: Double

    /// Does it have working code examples? (0.0-1.0)
    public let codeExamples: Double

    /// Does it include platform availability info? (0.0-1.0)
    public let hasAvailability: Double

    /// Is it focused on design/UX? (0.0-1.0)
    public let designFocus: Double

    /// Is it focused on language features? (0.0-1.0)
    public let languageFocus: Double

    /// Base search quality for this source (0.0-1.0)
    public let searchQuality: Double

    public init(
        authority: Double,
        freshness: Double,
        comprehensiveness: Double,
        codeExamples: Double,
        hasAvailability: Double,
        designFocus: Double,
        languageFocus: Double,
        searchQuality: Double
    ) {
        self.authority = authority
        self.freshness = freshness
        self.comprehensiveness = comprehensiveness
        self.codeExamples = codeExamples
        self.hasAvailability = hasAvailability
        self.designFocus = designFocus
        self.languageFocus = languageFocus
        self.searchQuality = searchQuality
    }

    /// Combined score for a given intent
    public func scoreFor(intent: QueryIntent) -> Double {
        switch intent {
        case .apiReference:
            return (authority * 0.4) + (comprehensiveness * 0.3) + (hasAvailability * 0.3)
        case .howTo:
            return (codeExamples * 0.5) + (authority * 0.3) + (freshness * 0.2)
        case .designGuidance:
            return (designFocus * 0.6) + (authority * 0.3) + (freshness * 0.1)
        case .languageFeature:
            return (languageFocus * 0.5) + (freshness * 0.3) + (authority * 0.2)
        case .conceptual:
            return (comprehensiveness * 0.4) + (authority * 0.3) + (languageFocus * 0.3)
        case .troubleshooting:
            return (codeExamples * 0.5) + (searchQuality * 0.3) + (comprehensiveness * 0.2)
        case .migration:
            return (freshness * 0.4) + (comprehensiveness * 0.3) + (authority * 0.3)
        case .packageDiscovery:
            return (freshness * 0.4) + (codeExamples * 0.3) + (searchQuality * 0.3)
        case .legacy:
            // Legacy prefers comprehensive historical coverage over freshness
            return (comprehensiveness * 0.5) + (codeExamples * 0.3) + (authority * 0.2)
        }
    }
}

/// Source properties for each source
/// Values determined empirically by testing 10 queries per source (Issue #81)
public enum SourcePropertiesRegistry {
    public static let properties: [SearchSource: SourceProperties] = [
        .appleDocs: SourceProperties(
            authority: 1.0, // Official Apple source
            freshness: 0.9, // Updated with each release
            comprehensiveness: 1.0, // Covers all APIs
            codeExamples: 0.3, // Mostly signatures only (empirical)
            hasAvailability: 1.0, // Full availability data
            designFocus: 0.2, // Some in overviews
            languageFocus: 0.2, // API-focused, not language
            searchQuality: 0.5 // BM25 ranking issues! (empirical)
        ),
        .samples: SourceProperties(
            authority: 1.0, // Official Apple samples
            freshness: 0.8, // Updated periodically
            comprehensiveness: 0.4, // Selective topics
            codeExamples: 1.0, // Pure working code! (empirical)
            hasAvailability: 0.5, // Implicit from project
            designFocus: 0.4, // Shows UI patterns
            languageFocus: 0.3, // Shows Swift usage
            searchQuality: 0.9 // Excellent results! (empirical)
        ),
        .hig: SourceProperties(
            authority: 1.0, // Official Apple HIG
            freshness: 0.9, // Updated regularly
            comprehensiveness: 0.7, // Design topics only
            codeExamples: 0.0, // No code! (empirical)
            hasAvailability: 0.3, // Platform sections
            designFocus: 1.0, // Pure design guidance (empirical)
            languageFocus: 0.0, // Not language-related
            searchQuality: 0.9 // Excellent results! (empirical)
        ),
        .appleArchive: SourceProperties(
            authority: 0.6, // May be outdated (empirical)
            freshness: 0.2, // Legacy 2013-2016 content (empirical)
            comprehensiveness: 0.9, // Historical coverage
            codeExamples: 0.7, // Objective-C/Swift examples
            hasAvailability: 0.3, // Old versions
            designFocus: 0.3, // Some design info
            languageFocus: 0.4, // Objective-C/Swift
            searchQuality: 0.6 // Mixed quality (empirical)
        ),
        .swiftEvolution: SourceProperties(
            authority: 0.9, // Official Swift process
            freshness: 1.0, // Latest proposals! (empirical)
            comprehensiveness: 0.5, // Language features only
            codeExamples: 0.8, // Proposal examples
            hasAvailability: 0.9, // Swift version info! (empirical)
            designFocus: 0.0, // Not design
            languageFocus: 1.0, // Pure language! (empirical)
            searchQuality: 0.9 // SE-XXXX format helps (empirical)
        ),
        .swiftOrg: SourceProperties(
            authority: 0.9, // Official Swift.org
            freshness: 0.9, // Kept current
            comprehensiveness: 0.6, // Core topics
            codeExamples: 0.7, // Has examples
            hasAvailability: 0.4, // Swift version info
            designFocus: 0.0, // No design
            languageFocus: 0.9, // Language-focused
            searchQuality: 0.7 // Good content
        ),
        .swiftBook: SourceProperties(
            authority: 1.0, // Official Swift book
            freshness: 0.9, // Updated with Swift
            comprehensiveness: 0.8, // Language coverage
            codeExamples: 0.9, // Many examples! (empirical)
            hasAvailability: 0.6, // Swift version
            designFocus: 0.0, // No design
            languageFocus: 1.0, // Pure language! (empirical)
            searchQuality: 0.9 // Well-structured (empirical)
        ),
        .packages: SourceProperties(
            authority: 0.5, // Community packages
            freshness: 0.9, // Active development
            comprehensiveness: 0.3, // Specific features
            codeExamples: 0.8, // Code packages
            hasAvailability: 0.2, // Package manifest
            designFocus: 0.0, // No design
            languageFocus: 0.4, // Swift packages
            searchQuality: 0.6 // Varies
        ),
    ]

    public static func properties(for source: SearchSource) -> SourceProperties {
        properties[source] ?? SourceProperties(
            authority: 0.5, freshness: 0.5, comprehensiveness: 0.5, codeExamples: 0.5,
            hasAvailability: 0.5, designFocus: 0.5, languageFocus: 0.5, searchQuality: 0.5
        )
    }
}

// MARK: - Unified Search Summary

/// Short summary of results from all sources (for "search all")
public struct UnifiedSearchSummary: Codable, Sendable {
    public let query: String
    public let totalResults: Int
    public let sourceSummaries: [SourceSummary]
    public let hints: [SourceHint]
    public let tips: [SearchTip]
    public let detectedIntent: QueryIntent

    public init(
        query: String,
        totalResults: Int,
        sourceSummaries: [SourceSummary],
        hints: [SourceHint] = [],
        tips: [SearchTip] = [],
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
        public let source: SearchSource
        public let count: Int
        public let topResult: TopResultPreview?
        public let hasMore: Bool

        public init(source: SearchSource, count: Int, topResult: TopResultPreview?, hasMore: Bool) {
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

// MARK: - Tip Factory (Common Tips)

/// Factory for creating common search tips
public enum SearchTipFactory {
    public static func noResultsTip(query: String) -> SearchTip {
        SearchTip(
            category: .refinement,
            message: "No results for '\(query)'. Try broader terms or check spelling.",
            actionHint: "Remove specific version numbers or use related framework names"
        )
    }

    public static func tryOtherSourceTip(current: SearchSource, suggested: SearchSource) -> SearchTip {
        SearchTip(
            category: .source,
            message: "Also check \(suggested.displayName) for \(suggested == .hig ? "design guidance" : "more context")",
            actionHint: "Use source: \(suggested.rawValue)"
        )
    }

    public static func availabilityTip(platform: String, minVersion: String) -> SearchTip {
        SearchTip(
            category: .availability,
            message: "This API requires \(platform) \(minVersion)+",
            actionHint: "Check availability before using in production"
        )
    }

    public static func deprecationTip(replacement: String?) -> SearchTip {
        SearchTip(
            category: .bestPractice,
            message: "This API is deprecated." + (replacement.map { " Use \($0) instead." } ?? ""),
            actionHint: replacement.map { "Search for \($0)" }
        )
    }

    public static func swiftEvolutionTip(proposalID: String) -> SearchTip {
        SearchTip(
            category: .related,
            message: "See Swift Evolution proposal \(proposalID) for background",
            actionHint: "Use source: swift-evolution for full proposal"
        )
    }

    public static func sampleCodeAvailableTip(count: Int) -> SearchTip {
        SearchTip(
            category: .source,
            message: "\(count) sample project\(count == 1 ? "" : "s") available with working code",
            actionHint: "Use source: samples to explore"
        )
    }

    public static func designGuidelineTip() -> SearchTip {
        SearchTip(
            category: .source,
            message: "Check Human Interface Guidelines for design best practices",
            actionHint: "Use source: hig"
        )
    }
}
