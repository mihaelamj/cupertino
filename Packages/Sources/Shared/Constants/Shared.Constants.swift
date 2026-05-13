import Foundation

// MARK: - Cupertino Constants

// swiftlint:disable type_body_length file_length
// Justification: Shared.Constants serves as central configuration hub for the entire application.
// Contains directory names, file names, URL patterns, limits, delays, and MCP configuration.
// Splitting would scatter related constants and reduce discoverability.
// Organized with clear MARK sections for easy navigation.

/// Global constants for Cupertino application
extension Shared.Constants {
    // MARK: - Directory Names

    /// Base directory name for Cupertino data
    public static let baseDirectoryName = ".cupertino"

    /// Subdirectory names
    public enum Directory {
        public static let docs = "docs"
        public static let swiftEvolution = "swift-evolution"
        public static let swiftOrg = "swift-org"
        public static let swiftBook = "swift-book"
        public static let packages = "packages"
        public static let sampleCode = "sample-code"
        public static let archive = "archive"
        public static let hig = "hig"
    }

    // MARK: - File Names

    public enum FileName {
        // MARK: Configuration Files

        /// Main metadata file for crawler state
        public static let metadata = "metadata.json"

        /// Configuration file
        public static let config = "config.json"

        /// TUI configuration file
        public static let tuiConfig = "tui-config.json"

        /// Application log file
        public static let logFile = "cupertino.log"

        /// Search database file
        public static let searchDatabase = "search.db"

        /// Samples database file
        public static let samplesDatabase = "samples.db"

        /// Package source + docs FTS index (separate from search.db; hidden feature)
        public static let packagesIndexDatabase = "packages.db"

        /// Stores the `databaseVersion` that was active when `setup` last succeeded.
        /// Read on subsequent setup invocations to distinguish stale DBs from current ones (#168).
        public static let setupVersionFile = ".setup-version"

        // MARK: Package Data Files

        /// Swift packages with GitHub stars data
        public static let packagesWithStars = "swift-packages-with-stars.json"

        /// Priority packages list (bundled)
        public static let priorityPackages = "priority-packages.json"

        /// User-selected packages file
        public static let selectedPackages = "selected-packages.json"

        /// User-maintained exclusion list (flat array of "owner/repo" strings)
        public static let excludedPackages = "excluded-packages.json"

        /// Machine-written transitive closure of seeds+exclusions (cache)
        public static let resolvedPackages = "resolved-packages.json"

        /// Per-repo GitHub canonical-name cache (owner/repo → redirect target)
        public static let canonicalOwnersCache = "canonical-owners.json"

        /// Package fetch checkpoint file
        public static let checkpoint = "checkpoint.json"

        /// Authentication cookies file
        public static let authCookies = ".auth-cookies.json"

        // MARK: File Extensions

        /// Markdown file extension
        public static let markdownExtension = ".md"

        /// JSON file extension
        public static let jsonExtension = ".json"
    }

    // MARK: - Default Paths

    /// Default base directory path: ~/.cupertino, unless overridden by a
    /// `cupertino.config.json` sitting next to the running executable
    /// (see `Shared.Constants.BinaryConfig`, #211).
    public static var defaultBaseDirectory: URL {
        if let override = Shared.Constants.BinaryConfig.shared.resolvedBaseDirectory {
            return override
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(baseDirectoryName)
    }

    /// Default docs directory: ~/.cupertino/docs
    public static var defaultDocsDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.docs)
    }

    /// Default Swift Evolution directory: ~/.cupertino/swift-evolution
    public static var defaultSwiftEvolutionDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.swiftEvolution)
    }

    /// Default Swift.org directory: ~/.cupertino/swift-org
    public static var defaultSwiftOrgDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.swiftOrg)
    }

    /// Default Swift Book directory: ~/.cupertino/swift-book
    public static var defaultSwiftBookDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.swiftBook)
    }

    /// Default packages directory: ~/.cupertino/packages
    public static var defaultPackagesDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.packages)
    }

    /// Default sample code directory: ~/.cupertino/sample-code
    public static var defaultSampleCodeDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.sampleCode)
    }

    /// Default archive directory: ~/.cupertino/archive
    public static var defaultArchiveDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.archive)
    }

    /// Default HIG directory: ~/.cupertino/hig
    public static var defaultHIGDirectory: URL {
        defaultBaseDirectory.appendingPathComponent(Directory.hig)
    }

    /// Default metadata file: ~/.cupertino/metadata.json
    public static var defaultMetadataFile: URL {
        defaultBaseDirectory.appendingPathComponent(FileName.metadata)
    }

    /// Default config file: ~/.cupertino/config.json
    public static var defaultConfigFile: URL {
        defaultBaseDirectory.appendingPathComponent(FileName.config)
    }

    /// Default search database: ~/.cupertino/search.db
    public static var defaultSearchDatabase: URL {
        defaultBaseDirectory.appendingPathComponent(FileName.searchDatabase)
    }

    /// Default package-index database: ~/.cupertino/packages.db
    public static var defaultPackagesDatabase: URL {
        defaultBaseDirectory.appendingPathComponent(FileName.packagesIndexDatabase)
    }

    // MARK: - Application Info

    public enum App {
        /// Application name
        public static let name = "Cupertino"

        /// Command name
        public static let commandName = "cupertino"

        /// MCP server name
        public static let mcpServerName = "cupertino"

        /// User agent for HTTP requests
        public static let userAgent = "CupertinoCrawler/1.0"

        /// Current version
        public static let version = "1.0.2"

        /// Database version - separate from CLI version, only bump when schema/content changes.
        /// Controls the cupertino-docs release tag that `cupertino setup` downloads from.
        /// v1.0.2 bumps from v1.0.0 to ship a re-indexed bundle: the v1.0.0 search.db
        /// carried 61,257 case-axis duplicate clusters covering 122,522 rows (#283), and
        /// the prior v1.0.1 "verified clean" claim used the wrong query column. The new
        /// v1.0.2 bundle was built with the post-#283 `URLUtilities.filename(_:)` against
        /// the full 404,729-page corpus (Studio v1.0.0 base + Claw fresh overlay) and
        /// verified: 277,640 documents, `GROUP BY LOWER(url) HAVING COUNT > 1` returns
        /// zero, schema `user_version` stamped 13.
        public static let databaseVersion = "1.0.2"

        /// Base URL for cupertino-docs release downloads. As of v1.0.0 the
        /// single `cupertino-databases-vX.zip` artifact bundles search.db,
        /// samples.db, and packages.db — earlier versions split packages.db
        /// into a separate `mihaelamj/cupertino-packages` companion repo
        /// which is now deprecated.
        public static let docsReleaseBaseURL = "https://github.com/mihaelamj/cupertino-docs/releases/download"

        /// Approximate database zip file size for progress display when Content-Length is unknown.
        /// v1.0.0 bundle is ~833 MB (search.db + samples.db + packages.db, DEFLATE-compressed).
        public static let approximateZipSize: Int64 = 850 * 1024 * 1024
    }

    // MARK: - Display Names

    public enum DisplayName {
        /// Swift.org display name (for log messages and UI)
        public static let swiftOrg = "Swift.org"

        /// Apple display name
        public static let apple = "Apple"

        // MARK: Documentation Type Display Names

        /// Apple Documentation display name
        public static let appleDocs = "Apple Documentation"

        /// Swift.org Documentation display name
        public static let swiftOrgDocs = "Swift.org Documentation"

        /// Swift Evolution Proposals display name
        public static let swiftEvolution = "Swift Evolution Proposals"

        /// Swift Package Documentation display name
        public static let swiftPackages = "Swift Package Documentation"

        /// All Documentation display name
        public static let allDocs = "All Documentation"

        // MARK: Fetch Type Display Names

        /// Swift Package Metadata display name
        public static let packageMetadata = "Swift Package Metadata"

        /// Apple Sample Code display name
        public static let sampleCode = "Apple Sample Code"

        /// Apple Archive Documentation display name
        public static let archive = "Apple Archive Documentation"

        /// Human Interface Guidelines display name
        public static let humanInterfaceGuidelines = "Human Interface Guidelines"
    }

    // MARK: - GitHub Organizations

    public enum GitHubOrg {
        /// Apple organization name (lowercase for comparisons)
        public static let apple = "apple"

        /// Apple organization display name
        public static let appleDisplay = "Apple"

        /// SwiftLang organization name (lowercase for comparisons)
        public static let swiftlang = "swiftlang"

        /// SwiftLang organization display name
        public static let swiftlangDisplay = "SwiftLang"

        /// Swift Server organization name (lowercase for comparisons)
        public static let swiftServer = "swift-server"

        /// Swift Server organization display name
        public static let swiftServerDisplay = "Swift Server"

        /// All official Swift organization names (lowercase)
        public static let officialOrgs = [apple, swiftlang, swiftServer]
    }

    // MARK: - Logging

    public enum Logging {
        /// Main subsystem identifier for logging
        public static let subsystem = "com.cupertino.cli"
    }

    // MARK: - Source Prefixes

    /// Source prefixes used for filtering search queries.
    /// Users can prefix their search with these to filter by source type.
    /// Example: "swift-evolution actors" searches only Swift Evolution for "actors"
    public enum SourcePrefix {
        /// Apple Developer Documentation source prefix
        public static let appleDocs = "apple-docs"

        /// Swift Book (The Swift Programming Language) source prefix
        public static let swiftBook = "swift-book"

        /// Swift.org documentation source prefix
        public static let swiftOrg = "swift-org"

        /// Swift Evolution proposals source prefix
        public static let swiftEvolution = "swift-evolution"

        /// Swift package documentation source prefix
        public static let packages = "packages"

        /// Apple sample code source prefix (short form)
        public static let samples = "samples"

        /// Apple sample code source prefix (long form, for backward compatibility)
        public static let appleSampleCode = "apple-sample-code"

        /// Apple archive documentation source prefix
        public static let appleArchive = "apple-archive"

        /// Human Interface Guidelines source prefix
        public static let hig = "hig"

        /// Search all sources at once
        public static let all = "all"

        /// All known source prefixes for query detection
        public static let allPrefixes: [String] = [
            appleDocs,
            swiftBook,
            swiftOrg,
            swiftEvolution,
            packages,
            samples,
            appleSampleCode,
            appleArchive,
            hig,
            all,
        ]

        // MARK: - Source Display Names

        /// Display name for Apple Documentation
        public static let nameAppleDocs = "Apple Documentation"
        /// Display name for Sample Code
        public static let nameSamples = "Sample Code"
        /// Display name for Human Interface Guidelines
        public static let nameHIG = "Human Interface Guidelines"
        /// Display name for Apple Archive
        public static let nameArchive = "Apple Archive"
        /// Display name for Swift Evolution
        public static let nameSwiftEvolution = "Swift Evolution"
        /// Display name for Swift.org
        public static let nameSwiftOrg = "Swift.org"
        /// Display name for Swift Book
        public static let nameSwiftBook = "Swift Book"
        /// Display name for Swift Packages
        public static let namePackages = "Swift Packages"

        // MARK: - Source Emojis

        /// Emoji for Apple Documentation
        public static let emojiAppleDocs = "📚"
        /// Emoji for Sample Code
        public static let emojiSamples = "📦"
        /// Emoji for Human Interface Guidelines
        public static let emojiHIG = "🎨"
        /// Emoji for Apple Archive
        public static let emojiArchive = "📜"
        /// Emoji for Swift Evolution
        public static let emojiSwiftEvolution = "🔄"
        /// Emoji for Swift.org
        public static let emojiSwiftOrg = "🦅"
        /// Emoji for Swift Book
        public static let emojiSwiftBook = "📖"
        /// Emoji for Swift Packages
        public static let emojiPackages = "📦"

        // MARK: - Source Info (Unified Metadata)

        /// Complete metadata for a search source
        public struct SourceInfo: Sendable {
            public let key: String
            public let name: String
            public let emoji: String

            public init(key: String, name: String, emoji: String) {
                self.key = key
                self.name = name
                self.emoji = emoji
            }
        }

        /// Apple Documentation source info
        public static let infoAppleDocs = SourceInfo(
            key: appleDocs,
            name: nameAppleDocs,
            emoji: emojiAppleDocs
        )

        /// Apple Archive source info
        public static let infoArchive = SourceInfo(
            key: appleArchive,
            name: nameArchive,
            emoji: emojiArchive
        )

        /// Sample Code source info
        public static let infoSamples = SourceInfo(
            key: samples,
            name: nameSamples,
            emoji: emojiSamples
        )

        /// Human Interface Guidelines source info
        public static let infoHIG = SourceInfo(
            key: hig,
            name: nameHIG,
            emoji: emojiHIG
        )

        /// Swift Evolution source info
        public static let infoSwiftEvolution = SourceInfo(
            key: swiftEvolution,
            name: nameSwiftEvolution,
            emoji: emojiSwiftEvolution
        )

        /// Swift.org source info
        public static let infoSwiftOrg = SourceInfo(
            key: swiftOrg,
            name: nameSwiftOrg,
            emoji: emojiSwiftOrg
        )

        /// Swift Book source info
        public static let infoSwiftBook = SourceInfo(
            key: swiftBook,
            name: nameSwiftBook,
            emoji: emojiSwiftBook
        )

        /// Swift Packages source info
        public static let infoPackages = SourceInfo(
            key: packages,
            name: namePackages,
            emoji: emojiPackages
        )

        /// All source infos in display order
        public static let allSourceInfos: [SourceInfo] = [
            infoAppleDocs,
            infoArchive,
            infoSamples,
            infoHIG,
            infoSwiftEvolution,
            infoSwiftOrg,
            infoSwiftBook,
            infoPackages,
        ]
    }

    // MARK: - URLs

    public enum BaseURL {
        // MARK: Apple Developer

        /// Base Apple Developer URL
        public static let appleDeveloper = "https://developer.apple.com"

        /// Apple Developer Documentation
        public static let appleDeveloperDocs = "https://developer.apple.com/documentation/"

        /// Apple Archive root (`/library/archive/`)
        public static let appleArchive = "https://developer.apple.com/library/archive/"

        /// Apple Archive Documentation root (`/library/archive/documentation/`)
        public static let appleArchiveDocs = "https://developer.apple.com/library/archive/documentation/"

        /// Apple Human Interface Guidelines
        public static let appleHIG = "https://developer.apple.com/design/human-interface-guidelines/"

        /// Apple Sample Code List (rendered HTML page)
        public static let appleSampleCode = "https://developer.apple.com/documentation/samplecode/"

        /// Apple Sample Code List (raw JSON catalog).
        /// Used by `SampleCodeDownloader.writeCatalogJSON` to dump fresh
        /// metadata next to the downloaded zips so `cupertino save`
        /// indexes from on-disk freshness instead of the embedded
        /// snapshot (#214).
        public static let appleSampleCodeJSON = "https://developer.apple.com/tutorials/data/documentation/samplecode.json"

        /// Apple DocC tutorials-data root. Used to compose JSON-API URLs
        /// (`appleTutorialsData + "/documentation/<framework>/<symbol>.json"`).
        public static let appleTutorialsData = "https://developer.apple.com/tutorials/data"

        /// Apple DocC tutorials-data documentation root.
        /// Used by AvailabilityFetcher and friends as the JSON-API base.
        public static let appleTutorialsDocs = "https://developer.apple.com/tutorials/data/documentation"

        /// Apple Developer Account
        public static let appleDeveloperAccount = "https://developer.apple.com/account/"

        // MARK: Swift.org

        /// Swift.org Documentation Base (www.swift.org for general docs)
        public static let swiftOrg = "https://www.swift.org/documentation/"

        /// Swift Book Documentation (hosted at docs.swift.org)
        public static let swiftBook = "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/"

        /// Swift Book base URL (without specific path)
        public static let swiftBookBase = "https://docs.swift.org/swift-book"

        /// Swift.org base URL (without path)
        public static let swiftOrgBase = "https://swift.org"

        // MARK: Swift Evolution

        /// Swift Evolution Proposals on GitHub
        public static let swiftEvolution = "https://github.com/swiftlang/swift-evolution"

        // MARK: Swift Package Index

        /// Swift Package Index
        public static let swiftPackageIndex = "https://swiftpackageindex.com"

        // MARK: GitHub

        /// GitHub base URL
        public static let github = "https://github.com"

        /// GitHub API Base
        public static let githubAPI = "https://api.github.com"

        /// GitHub API Repos Endpoint Template (use with owner/repo)
        public static let githubAPIRepos = "https://api.github.com/repos"

        /// GitHub Raw Content Base URL
        public static let githubRaw = "https://raw.githubusercontent.com"

        /// SwiftPackageIndex Package List
        public static let swiftPackageList =
            "https://raw.githubusercontent.com/SwiftPackageIndex/PackageList/main/packages.json"
    }

    // MARK: - URL Templates

    public enum URLTemplate {
        /// GitHub repository URL template
        /// Usage: URLTemplate.githubRepo(owner: "apple", repo: "swift")
        public static func githubRepo(owner: String, repo: String) -> String {
            "\(BaseURL.github)/\(owner)/\(repo)"
        }

        /// GitHub repository URL (raw string format for pattern matching contexts)
        /// Usage: `url: "\(Shared.Constants.URLTemplate.githubRepoFormat(owner: owner, repo: repo))"`
        public static func githubRepoFormat(owner: String, repo: String) -> String {
            githubRepo(owner: owner, repo: repo)
        }
    }

    // MARK: - Regex Patterns

    public enum Pattern {
        /// GitHub URL pattern: https://github.com/owner/repo or https://github.com/owner/repo.git
        public static let githubURL = #"https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$"#

        /// GitHub URL pattern (lenient): Matches various GitHub URL formats
        public static let githubURLLenient = #"https://github\.com/([^/\s\)\"]+)/([^/\s\)\"\.]+)"#

        /// HTML anchor tag href extraction
        public static let htmlHref = #"<a[^>]*href=[\"']([^\"']*)[\"']"#

        /// Swift Evolution proposal number
        public static let seProposalNumber = #"^(?:SE-)?(\d{4})"#

        /// Swift Evolution status in markdown (supports both "* Status:" and "- Status:")
        public static let seStatus = #"[\*\-] Status:\s*\*\*([^\*]+)\*\*"#

        /// HTML pre/code block with language
        public static let htmlCodeBlockWithLanguage =
            #"<pre[^>]*>\s*<code\s+class=[\"'](?:language-)?(\w+)[\"'][^>]*>(.*?)</code>\s*</pre>"#

        /// Swift Evolution reference (SE-NNNN)
        public static let seReference = #"(SE-\d+)"#

        /// Swift Evolution or Swift Testing reference (SE-NNNN or ST-NNNN)
        public static let evolutionReference = #"((?:SE|ST)-\d+)"#
    }

    // MARK: - HTTP Headers

    public enum HTTPHeader {
        /// GitHub API Accept header
        public static let githubAccept = "application/vnd.github.v3+json"

        /// Authorization header name
        public static let authorization = "Authorization"

        /// Accept header name
        public static let accept = "Accept"

        /// User-Agent header name
        public static let userAgent = "User-Agent"
    }

    // MARK: - Environment Variables

    public enum EnvVar {
        /// GitHub token environment variable
        public static let githubToken = "GITHUB_TOKEN"

        /// Cupertino docs token environment variable (for database releases)
        public static let cupertinoDocsToken = "CUPERTINO_DOCS_TOKEN"
    }

    // MARK: - Search Constants

    /// Search-related constants shared by CLI and MCP
    public enum Search {
        // MARK: Resource URI Schemes

        /// Apple documentation resource URI scheme
        public static let appleDocsScheme = "apple-docs://"

        /// Apple archive documentation resource URI scheme
        public static let appleArchiveScheme = "apple-archive://"

        /// Swift Evolution proposal resource URI scheme
        public static let swiftEvolutionScheme = "swift-evolution://"

        /// Human Interface Guidelines resource URI scheme
        public static let higScheme = "hig://"

        // MARK: Tool Names

        /// Unified search tool name (replaces search_docs, search_hig, search_all, search_samples)
        public static let toolSearch = "search"

        /// List frameworks tool name
        public static let toolListFrameworks = "list_frameworks"

        /// Read document tool name
        public static let toolReadDocument = "read_document"

        // MARK: Sample Code Tool Names

        /// List samples tool name
        public static let toolListSamples = "list_samples"

        /// Read sample tool name
        public static let toolReadSample = "read_sample"

        /// Read sample file tool name
        public static let toolReadSampleFile = "read_sample_file"

        // MARK: Semantic Search Tool Names (#81)

        /// Search symbols tool name (semantic code search)
        public static let toolSearchSymbols = "search_symbols"

        /// Search property wrappers tool name
        public static let toolSearchPropertyWrappers = "search_property_wrappers"

        /// Search concurrency patterns tool name
        public static let toolSearchConcurrency = "search_concurrency"

        /// Search protocol conformances tool name
        public static let toolSearchConformances = "search_conformances"

        // MARK: Swift Evolution

        /// Swift Evolution proposal ID prefix
        public static let sePrefix = "SE-"

        /// Swift Testing proposal ID prefix
        public static let stPrefix = "ST-"

        // MARK: JSON Schema

        /// JSON Schema type: object
        public static let schemaTypeObject = "object"

        /// JSON Schema parameter: query
        public static let schemaParamQuery = "query"

        /// JSON Schema parameter: source
        public static let schemaParamSource = "source"

        /// JSON Schema parameter: framework
        public static let schemaParamFramework = "framework"

        /// JSON Schema parameter: language
        public static let schemaParamLanguage = "language"

        /// JSON Schema parameter: include_archive
        public static let schemaParamIncludeArchive = "include_archive"

        /// JSON Schema parameter: platform (for HIG)
        public static let schemaParamPlatform = "platform"

        /// JSON Schema parameter: category (for HIG)
        public static let schemaParamCategory = "category"

        /// JSON Schema parameter: limit
        public static let schemaParamLimit = "limit"

        /// JSON Schema parameter: uri
        public static let schemaParamURI = "uri"

        /// JSON Schema parameter: format
        public static let schemaParamFormat = "format"

        /// JSON Schema parameter: project_id
        public static let schemaParamProjectId = "project_id"

        /// JSON Schema parameter: file_path
        public static let schemaParamFilePath = "file_path"

        /// JSON Schema parameter: search_files
        public static let schemaParamSearchFiles = "search_files"

        /// JSON Schema parameter: min_ios
        public static let schemaParamMinIOS = "min_ios"

        /// JSON Schema parameter: min_macos
        public static let schemaParamMinMacOS = "min_macos"

        /// JSON Schema parameter: min_tvos
        public static let schemaParamMinTvOS = "min_tvos"

        /// JSON Schema parameter: min_watchos
        public static let schemaParamMinWatchOS = "min_watchos"

        /// JSON Schema parameter: min_visionos
        public static let schemaParamMinVisionOS = "min_visionos"

        // MARK: Semantic Search Parameters (#81)

        /// JSON Schema parameter: kind (symbol kind)
        public static let schemaParamKind = "kind"

        /// JSON Schema parameter: is_async (async functions filter)
        public static let schemaParamIsAsync = "is_async"

        /// JSON Schema parameter: wrapper (property wrapper name)
        public static let schemaParamWrapper = "wrapper"

        /// JSON Schema parameter: pattern (concurrency pattern)
        public static let schemaParamPattern = "pattern"

        /// JSON Schema parameter: protocol (protocol conformance)
        public static let schemaParamProtocol = "protocol"

        /// Format value: json
        public static let formatValueJSON = "json"

        /// Format value: markdown
        public static let formatValueMarkdown = "markdown"

        // MARK: Messages & Tips

        /// Tip for using resources/read
        public static let tipUseResourcesRead =
            "💡 **Tip:** Use `resources/read` with the URI to get the full document content."

        /// Tip for filtering by framework
        public static let tipFilterByFramework =
            "💡 **Tip:** Use `search` with the `framework` parameter to filter results."

        /// No results found message
        public static let messageNoResults = """
        _No results found. Try different keywords or check available frameworks \
        using `list_frameworks`._

        💡 **Try other sources:** Use `source` parameter: samples, hig, apple-archive, \
        swift-evolution, swift-org, swift-book, packages, or `all`.
        """

        /// No frameworks found message
        public static func messageNoFrameworks(buildIndexCommand: String) -> String {
            """
            _No frameworks found. The search index may be empty. \
            Run `\(buildIndexCommand)` to index your documentation._
            """
        }

        /// Tip for exploring other sources when results are limited
        public static let tipExploreOtherSources = """
        💡 **Need more?** Try these additional sources:
        - `search` with `source: apple-archive` for foundational guides \
        (Core Animation, Quartz 2D, KVO/KVC, threading)
        - `search` with `source: samples` for working code examples
        """

        /// Tip for archive when no results
        public static let tipTryArchive = """
        💡 **Tip:** For conceptual/foundational topics, try `search` with \
        `source: apple-archive` to search Apple Archive legacy programming guides.
        """

        /// Tip for platform availability filters
        public static let tipPlatformFilters = """
        💡 **Tip:** Filter by platform: `\(schemaParamMinIOS)`, `\(schemaParamMinMacOS)`, \
        `\(schemaParamMinTvOS)`, `\(schemaParamMinWatchOS)`, `\(schemaParamMinVisionOS)`
        """

        /// All available source values (excluding 'all')
        public static let availableSources: [String] = [
            SourcePrefix.appleDocs,
            SourcePrefix.samples,
            SourcePrefix.hig,
            SourcePrefix.appleArchive,
            SourcePrefix.swiftEvolution,
            SourcePrefix.swiftOrg,
            SourcePrefix.swiftBook,
            SourcePrefix.packages,
        ]

        /// Get all sources except the specified one(s)
        public static func otherSources(excluding current: String?) -> [String] {
            let excluded = current ?? ""
            return availableSources.filter { $0 != excluded }
        }

        /// Comprehensive tips showing all available search capabilities
        public static let tipSearchCapabilities = """
        💡 **Dig deeper:** Use `source` parameter to search: \(availableSources.joined(separator: ", ")), or `all`.
        """

        /// Tip for semantic code search tools (#81)
        public static let tipSemanticSearch = """
        🔍 **AST search:** Use `\(toolSearchSymbols)`, `\(toolSearchPropertyWrappers)`, \
        `\(toolSearchConcurrency)`, or `\(toolSearchConformances)` for semantic code \
        discovery via AST extraction.
        """

        /// Generate tip showing other sources for a specific search
        public static func tipOtherSources(excluding current: String?) -> String {
            let others = otherSources(excluding: current)
            return "💡 **Other sources:** \(others.joined(separator: ", ")), or `all`"
        }

        // MARK: Formatting

        /// Score number format (2 decimal places)
        public static let formatScore = "%.2f"
    }

    // MARK: - CLI Commands

    public enum Command {
        /// Build index command name
        public static let buildIndex = "build-index"

        /// Crawl command name
        public static let crawl = "crawl"

        /// Serve command name (MCP)
        public static let serve = "serve"
    }

    // MARK: - Messages

    public enum Message {
        // MARK: GitHub Token Instructions

        /// Export GitHub token instruction (for bash shell)
        public static let exportGitHubToken = "export GITHUB_TOKEN=your_token_here"

        /// GitHub rate limit without token
        public static let rateLimitWithoutToken = "Without token: 60 requests/hour"

        /// GitHub rate limit with token
        public static let rateLimitWithToken = "With token: 5000 requests/hour"

        /// Tip about setting GitHub token
        public static let gitHubTokenTip = "💡 Tip: Set GITHUB_TOKEN environment variable for higher rate limits"
    }

    // MARK: - Delays and Timeouts

    /// Network delays and timeout values
    public enum Delay {
        /// Delay between Swift Evolution proposal fetches
        /// Rationale: GitHub API rate limiting (60 req/hour without token)
        public static let swiftEvolution: Duration = .milliseconds(500)

        /// Delay between sample code page loads
        /// Rationale: Avoid overwhelming Apple's servers
        public static let sampleCodeBetweenPages: Duration = .seconds(1)

        /// Wait time for sample code page to load completely
        /// Rationale: JavaScript-heavy pages need time to render
        public static let sampleCodePageLoad: Duration = .seconds(5)

        /// Delay after sample code page interaction
        /// Rationale: Wait for UI state to update
        public static let sampleCodeInteraction: Duration = .seconds(3)

        /// Delay before sample code download
        /// Rationale: Ensure download link is ready
        public static let sampleCodeDownload: Duration = .seconds(2)

        /// Rate limit delay for package fetching (high priority packages)
        /// Rationale: GitHub API secondary rate limits
        public static let packageFetchHighPriority: Duration = .seconds(5)

        /// Rate limit delay for package fetching (normal priority)
        /// Rationale: Balance speed vs API limits
        public static let packageFetchNormal: Duration = .seconds(1.2)

        /// Rate limit delay for package star count (high priority)
        /// Rationale: Star count fetches are lighter, can be faster
        public static let packageStarsHighPriority: Duration = .seconds(2)

        /// Rate limit delay for package star count (normal)
        /// Rationale: Minimize total fetch time
        public static let packageStarsNormal: Duration = .seconds(0.5)

        /// Delay between archive page fetches
        /// Rationale: Respectful crawling of Apple's archive servers
        public static let archivePage: Duration = .milliseconds(500)

        /// Base pause before retry after failure. Used as the base for
        /// exponential backoff (1s → 3s → 9s …) so successive retries
        /// span enough time to outlast typical Apple JSON-API rate-limit
        /// bursts (#209). The original 2026-04-30 recrawl saw 192/360k
        /// pages fail at fixed 1-second intervals; a retry minutes later
        /// recovered 187/192 — confirming the failures were rate-limit
        /// windows the fixed delay never escaped.
        public static let retryPause: Duration = .seconds(1)

        /// Multiplier for exponential retry backoff (#209). With base
        /// 1s and multiplier 3, attempts wait 1s, 3s, 9s — total 13s of
        /// retry-window coverage instead of the previous 3s.
        public static let retryBackoffMultiplier: Double = 3.0

        /// Cap on a single retry sleep (#209). Prevents runaway sleeps
        /// if maxRetries is ever bumped well past 3.
        public static let retryBackoffMax: Duration = .seconds(30)

        /// Compute the sleep duration for the n-th retry (1-indexed):
        /// `base * multiplier^(attempt - 1)`, capped at `retryBackoffMax`.
        ///
        /// With defaults (base 1s, multiplier 3): attempt 1 → 1s,
        /// attempt 2 → 3s, attempt 3 → 9s. Total wait across 3 retries:
        /// 13s — long enough to outlast typical Apple rate-limit bursts
        /// (#209). Returns `.zero` for attempt < 1 so the helper is
        /// safe to call unconditionally.
        public static func retryBackoff(
            attempt: Int,
            base: Duration = retryPause,
            multiplier: Double = retryBackoffMultiplier,
            maxDelay: Duration = retryBackoffMax
        ) -> Duration {
            guard attempt >= 1 else { return .zero }

            // Reduce the base Duration to a Double of seconds so we can
            // multiply by `multiplier^(attempt-1)`. Foundation's Duration
            // doesn't expose direct fractional-second multiplication.
            let parts = base.components
            let baseSeconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            let factor = pow(multiplier, Double(attempt - 1))
            let computed = baseSeconds * factor

            let capParts = maxDelay.components
            let capSeconds = Double(capParts.seconds) + Double(capParts.attoseconds) / 1e18

            let bounded = min(computed, capSeconds)
            let wholeSeconds = Int64(bounded)
            let fractional = bounded - Double(wholeSeconds)
            let attoseconds = Int64(fractional * 1e18)
            return Duration(secondsComponent: wholeSeconds, attosecondsComponent: attoseconds)
        }
    }

    /// Timeout values for operations
    public enum Timeout {
        /// Timeout for page loading in crawler
        /// Rationale: Complex pages can take time, but 30s is reasonable limit
        public static let pageLoad: Duration = .seconds(30)

        /// Maximum time to wait for WKWebView navigation
        /// Rationale: Matches page load timeout for consistency
        public static let webViewNavigation: Duration = .seconds(30)

        /// Time to wait for JavaScript execution
        /// Rationale: Allow JS to populate dynamic content
        public static let javascriptWait: Duration = .seconds(5)

        /// Time to wait for JavaScript in HIG SPA
        /// Rationale: HIG pages are simpler, 3s is sufficient
        public static let higJavascriptWait: Duration = .seconds(3)
    }

    // MARK: - Intervals

    /// Periodic operation intervals
    public enum Interval {
        /// Auto-save interval for crawler state
        /// Rationale: Balance between data safety and I/O overhead
        public static let autoSave: TimeInterval = 30.0

        /// Log progress every N items
        /// Rationale: Enough to show progress without spamming logs
        public static let progressLogEvery: Int = 50

        /// Recycle WKWebView every N pages to prevent memory buildup
        /// Rationale: Prevents WebKit memory leaks during long crawl sessions
        public static let webViewRecycleEvery: Int = 50
    }

    // MARK: - Content Limits

    /// Content size and length limits
    public enum ContentLimit {
        /// Maximum length for summary extraction (characters)
        /// Rationale: Enough for declaration + overview of properties/methods
        public static let summaryMaxLength: Int = 1500

        /// Maximum content preview length (characters)
        /// Rationale: Shorter preview for quick display
        public static let previewMaxLength: Int = 200
    }

    // MARK: - Swift Evolution

    /// Swift Evolution repository configuration
    public enum SwiftEvolution {
        /// Swift Evolution repository (owner/repo format)
        public static let repository = "swiftlang/swift-evolution"

        /// Default branch to fetch from
        public static let branch = "main"

        /// Repository owner
        public static let owner = "swiftlang"

        /// Repository name
        public static let repo = "swift-evolution"

        /// Subdirectory path for Swift Evolution proposals
        public static let proposalsSubdirectory = "proposals"

        /// Subdirectory path for Swift Testing proposals
        public static let testingSubdirectory = "proposals/testing"

        /// Proposal ID prefix for Swift Evolution
        public static let seIDPrefix = "SE"

        /// Proposal ID prefix for Swift Testing
        public static let stIDPrefix = "ST"
    }

    // MARK: - Priority Packages

    /// Critical Apple packages that should always be included
    public enum CriticalApplePackages {
        /// List of critical Apple package repository names
        /// These are the most commonly used Apple packages and should be prioritized
        public static let repositories: [String] = [
            "swift",
            "swift-algorithms",
            "swift-argument-parser",
            "swift-asn1",
            "swift-async-algorithms",
            "swift-atomics",
            "swift-cassandra-client",
            "swift-certificates",
            "swift-cluster-membership",
            "swift-collections",
            "swift-crypto",
            "swift-distributed-actors",
            "swift-docc",
            "swift-driver",
            "swift-format",
            "swift-log",
            "swift-metrics",
            "swift-nio",
            "swift-nio-http2",
            "swift-nio-ssl",
            "swift-nio-transport-services",
            "swift-numerics",
            "swift-openapi-generator",
            "swift-openapi-runtime",
            "swift-openapi-urlsession",
            "swift-package-manager",
            "swift-protobuf",
            "swift-service-context",
            "swift-system",
            "swift-testing",
            "sourcekit-lsp",
        ]
    }

    /// Well-known ecosystem packages
    public enum KnownEcosystemPackages {
        /// List of well-known ecosystem packages (owner/repo format)
        /// Note: Excludes deprecated packages (Alamofire, RxSwift, etc.)
        public static let repositories: [String] = [
            "vapor/vapor",
            "vapor/swift-getting-started-web-server",
            "pointfreeco/swift-composable-architecture",
            "pointfreeco/swift-custom-dump",
            "pointfreeco/swift-dependencies",
        ]
    }

    // MARK: - CLI Help Strings

    /// Help text for CLI commands and options
    public enum HelpText {
        /// Apple documentation directory help text
        public static let docsDir = "Apple documentation directory"

        /// Swift Evolution proposals directory help text
        public static let evolutionDir = "Swift Evolution proposals directory"

        /// Search database path help text
        public static let searchDB = "Search database path"

        /// MCP server abstract description
        public static let mcpAbstract =
            "MCP Server for Apple Documentation, Swift Evolution, Swift Packages, and Code Samples"
    }

    // MARK: - Host Domain Identifiers

    /// Domain identifiers for URL classification
    public enum HostDomain {
        /// Swift.org domain identifier
        public static let swiftOrg = "swift.org"

        /// Apple.com domain identifier
        public static let appleCom = "apple.com"
    }

    // MARK: - Path Components

    /// Common path components for URL classification
    public enum PathComponent {
        /// Swift Book path component
        public static let swiftBook = "swift-book"

        /// Swift.org framework identifier
        public static let swiftOrgFramework = "swift-org"
    }

    // MARK: - URL Cleanup Patterns

    /// URL patterns for cleanup and normalization
    public enum URLCleanupPattern {
        /// Swift.org base URL for cleanup
        public static let swiftOrgWWW = "https://www.swift.org/"
    }

    // MARK: - JSON-RPC Message Fields

    /// Field names for JSON-RPC message parsing
    public enum JSONRPCField {
        /// ID field
        public static let id = "id"

        /// Method field
        public static let method = "method"

        /// Error field
        public static let error = "error"

        /// Result field
        public static let result = "result"
    }

    // MARK: - Error Messages

    /// Error message constants
    public enum ErrorMessage {
        /// Invalid JSON-RPC message type error
        public static let invalidJSONRPCMessage = "Unable to determine JSON-RPC message type"
    }

    // MARK: - JavaScript Code

    public enum JavaScript {
        /// Get the full HTML content of the current document
        public static let getDocumentHTML = "document.documentElement.outerHTML"
    }

    // MARK: - Default Limits

    public enum Limit {
        // MARK: Crawler Limits

        /// Default maximum number of pages to crawl. Effectively uncapped —
        /// 1 million is well above Apple's full developer docs (~70k pages),
        /// Swift Evolution (~500), Swift.org, HIG, and the archive combined,
        /// so a default crawl runs to queue exhaustion rather than hitting
        /// an artificial limit. Override with `--max-pages` if you need a
        /// smaller bounded crawl for testing.
        public static let defaultMaxPages = 1000000

        // MARK: File Size Limits

        /// Maximum file size for indexing (1 MiB)
        public static let maxIndexableFileSize = 1048576

        // MARK: Search Limits

        /// Default search result limit
        public static let defaultSearchLimit = 20

        /// Default list result limit (for listing samples, etc.)
        public static let defaultListLimit = 50

        /// Maximum search result limit
        public static let maxSearchLimit = 100

        /// Teaser result limit (for showing hints from alternate sources)
        public static let teaserLimit = 2

        // MARK: Display Limits

        /// Number of top packages to display
        public static let topPackagesDisplay = 20

        /// Maximum length for summary text in search results
        public static let summaryTruncationLength = 800
    }

    // MARK: - Database Schema

    public enum Database {
        // MARK: Table Names

        /// Main FTS5 search table name
        public static let tableDocsFTS = "docs_fts"

        /// Documents metadata table name
        public static let tableDocsMetadata = "docs_metadata"

        /// Packages table name
        public static let tablePackages = "packages"

        /// Package dependencies table name
        public static let tablePackageDependencies = "package_dependencies"

        // MARK: Column Names - docs_metadata

        /// URI column (primary key)
        public static let colURI = "uri"

        /// Framework column
        public static let colFramework = "framework"

        /// File path column
        public static let colFilePath = "file_path"

        /// Content hash column
        public static let colContentHash = "content_hash"

        /// Last crawled timestamp column
        public static let colLastCrawled = "last_crawled"

        /// Word count column
        public static let colWordCount = "word_count"

        /// Source type column
        public static let colSourceType = "source_type"

        /// Package ID column (foreign key)
        public static let colPackageID = "package_id"

        // MARK: Column Names - docs_fts

        /// Title column (FTS)
        public static let colTitle = "title"

        /// Summary column (FTS)
        public static let colSummary = "summary"

        /// Content column (FTS)
        public static let colContent = "content"

        // MARK: Column Names - packages

        /// Package ID column
        public static let colID = "id"

        /// Package name column
        public static let colName = "name"

        /// Package owner column
        public static let colOwner = "owner"

        /// Repository URL column
        public static let colRepositoryURL = "repository_url"

        /// Documentation URL column
        public static let colDocumentationURL = "documentation_url"

        /// Stars count column
        public static let colStars = "stars"

        /// Last updated timestamp column
        public static let colLastUpdated = "last_updated"

        /// Is Apple official flag column
        public static let colIsAppleOfficial = "is_apple_official"

        /// Description column
        public static let colDescription = "description"

        // MARK: Index Names

        /// Framework index name
        public static let idxFramework = "idx_framework"

        /// Source type index name
        public static let idxSourceType = "idx_source_type"

        /// Package owner index name
        public static let idxPackageOwner = "idx_package_owner"

        /// Package official flag index name
        public static let idxPackageOfficial = "idx_package_official"

        // MARK: Default Values

        /// Default source type for Apple documentation
        public static let defaultSourceTypeApple = "apple"

        // MARK: SQL Functions

        /// BM25 ranking function name
        public static let funcBM25 = "bm25"

        /// COUNT aggregate function
        public static let funcCount = "COUNT"
    }

    // MARK: - Priority Package List

    public enum PriorityPackage {
        /// Priority package list version
        public static let version = "1.0"

        // MARK: Tier Descriptions

        /// Tier 1 description (Apple official packages)
        public static let tier1Description = "Apple official packages - always crawled first"

        /// Tier 2 description (SwiftLang packages)
        public static let tier2Description = "SwiftLang official packages - core Swift tooling and infrastructure"

        /// Tier 3 description (Swift Server packages)
        public static let tier3Description = "Swift Server Work Group packages - mentioned in Swift.org docs"

        /// Tier 4 description (Ecosystem packages)
        public static let tier4Description = "Popular ecosystem packages mentioned in Swift.org documentation"

        // MARK: Package List Metadata

        /// Package list description
        public static let listDescription = """
        Priority Swift packages to always include in documentation crawling. \
        Auto-generated from Swift.org documentation analysis.
        """

        /// Update policy for priority package list
        public static let updatePolicy = "Regenerate this list whenever Swift.org documentation is re-crawled"

        /// Data sources for priority package list
        public static let sources: [String] = [
            "Swift.org official documentation",
            "Apple developer ecosystem",
            "Swift Evolution proposals",
        ]

        /// Notes about priority package list
        public static let notes: [String] = [
            "This file is automatically generated by analyzing Swift.org documentation",
            "Packages are categorized by source and importance",
            "Tier 1 (Apple official) should always be crawled",
            "Tier 2 (SwiftLang) provides core Swift tooling",
            "Tier 3 (Server) for server-side Swift applications",
            "Tier 4 (Ecosystem) includes popular community packages",
            "Re-generate this file when Swift.org docs are updated",
        ]
    }
}
