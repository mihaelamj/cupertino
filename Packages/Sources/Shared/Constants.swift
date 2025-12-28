import Foundation

// MARK: - Cupertino Constants

// swiftlint:disable type_body_length file_length
// Justification: Shared.Constants serves as central configuration hub for the entire application.
// Contains directory names, file names, URL patterns, limits, delays, and MCP configuration.
// Splitting would scatter related constants and reduce discoverability.
// Organized with clear MARK sections for easy navigation.

/// Global constants for Cupertino application
extension Shared {
    public enum Constants {
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

            // MARK: Package Data Files

            /// Swift packages with GitHub stars data
            public static let packagesWithStars = "swift-packages-with-stars.json"

            /// Priority packages list (bundled)
            public static let priorityPackages = "priority-packages.json"

            /// User-selected packages file
            public static let selectedPackages = "selected-packages.json"

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

        /// Default base directory path: ~/.cupertino
        public static var defaultBaseDirectory: URL {
            FileManager.default.homeDirectoryForCurrentUser
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
            public static let version = "0.8.2"

            /// Approximate database zip file size for progress display when Content-Length is unknown.
            /// NOTE: Update this after each database release (current: v0.8.1 ~400MB)
            public static let approximateZipSize: Int64 = 400 * 1024 * 1024
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

            /// Apple Archive Documentation
            public static let appleArchive = "https://developer.apple.com/library/archive/"

            /// Apple Human Interface Guidelines
            public static let appleHIG = "https://developer.apple.com/design/human-interface-guidelines/"

            /// Apple Sample Code List
            public static let appleSampleCode = "https://developer.apple.com/documentation/samplecode/"

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

            /// Swift Evolution status in markdown
            public static let seStatus = #"\* Status: \*\*([^\*]+)\*\*"#

            /// HTML pre/code block with language
            public static let htmlCodeBlockWithLanguage =
                #"<pre[^>]*>\s*<code\s+class=[\"'](?:language-)?(\w+)[\"'][^>]*>(.*?)</code>\s*</pre>"#

            /// Swift Evolution reference (SE-NNNN)
            public static let seReference = #"(SE-\d+)"#
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

            // MARK: Resource Template URIs

            /// Apple documentation resource template
            public static let templateAppleDocs = "apple-docs://{framework}/{page}"

            /// Swift Evolution resource template
            public static let templateSwiftEvolution = "swift-evolution://{proposalID}"

            // MARK: Resource Descriptions

            /// Apple documentation resource description prefix
            public static let appleDocsDescriptionPrefix = "Apple Documentation:"

            /// Swift Evolution proposal resource description
            public static let swiftEvolutionDescription = "Swift Evolution Proposal"

            /// Apple documentation template name
            public static let appleDocsTemplateName = "Apple Documentation Page"

            /// Apple documentation template description
            public static let appleDocsTemplateDescription = "Access Apple documentation by framework and page name"

            /// Swift Evolution template description
            public static let swiftEvolutionTemplateDescription =
                "Access Swift Evolution proposals by ID (e.g., SE-0001)"

            // MARK: MIME Types

            /// Markdown MIME type
            public static let mimeTypeMarkdown = "text/markdown"

            // MARK: Swift Evolution

            /// Swift Evolution proposal ID prefix
            public static let sePrefix = "SE-"

            // MARK: Tool Descriptions

            /// Unified search tool description
            public static let toolSearchDescription = """
            Search Apple documentation and Swift Evolution proposals by keywords. \
            Returns a ranked list of relevant documents with URIs that can be read using resources/read.

            **By default, searches ALL sources** (docs, samples, HIG, etc.) for comprehensive results. \
            Use `source` parameter to narrow to a specific source.

            **Semantic search:** Includes AST-extracted symbols from Swift source code. \
            Find @Observable classes, async functions, View conformances, protocol conformances, etc. \
            Works across both documentation and sample code.

            **Source options** (use `source` parameter to narrow scope):
            - (default): Search ALL sources at once
            - apple-docs: Modern Apple API documentation only
            - samples: Sample code projects with working examples
            - hig: Human Interface Guidelines
            - apple-archive: Legacy guides (Core Animation, Quartz 2D, KVO/KVC)
            - swift-evolution: Swift Evolution proposals
            - swift-org: Swift.org documentation
            - swift-book: The Swift Programming Language book
            - packages: Swift package documentation

            **IMPORTANT:** For foundational topics (Core Animation, Quartz 2D, KVO/KVC, threading), \
            use source=apple-archive. For working code examples, use source=samples.

            **Optional parameters:**
            - source: Filter by documentation source (see above)
            - framework: Filter by framework (e.g. swiftui, foundation)
            - include_archive: Include archive results when source is not specified
            - min_ios/min_macos/min_tvos/min_watchos/min_visionos: Filter by API availability
            - limit: Maximum results (default 20)
            """

            /// List frameworks tool description
            public static let toolListFrameworksDescription = """
            List all available frameworks in the documentation index with document counts. \
            Useful for discovering what documentation is available.
            """

            /// Read document tool description
            public static let toolReadDocumentDescription = """
            Read a document by URI. Returns the full document content in the requested format. \
            Use URIs from search_docs results. Format parameter: 'json' (default, structured) or 'markdown' (rendered).
            """

            // MARK: Sample Code Tool Descriptions

            /// List samples tool description
            public static let toolListSamplesDescription = """
            List all indexed Apple sample code projects with metadata. \
            Useful for discovering available sample code before searching.
            """

            /// Read sample tool description
            public static let toolReadSampleDescription = """
            Read a sample code project's README and metadata by project ID. \
            Use project IDs from search_samples or list_samples results.
            """

            /// Read sample file tool description
            public static let toolReadSampleFileDescription = """
            Read a specific source file from a sample code project. \
            Requires project_id and file_path parameters. File paths are relative to project root.
            """

            // MARK: Semantic Search Tool Descriptions (#81)

            /// Search symbols tool description
            public static let toolSearchSymbolsDescription = """
            Search Swift symbols by type and name pattern. Uses SwiftSyntax AST extraction. \
            Find structs, classes, actors, protocols, functions, properties by kind and name.

            **Symbol kinds:** struct, class, actor, enum, protocol, extension, function, property, typealias

            **Parameters:**
            - query: Symbol name pattern (partial match supported)
            - kind: Filter by symbol kind (optional)
            - is_async: Filter async functions only (optional)
            - framework: Filter by framework (optional)
            - limit: Maximum results (default 20)

            **Examples:**
            - Find all actors: kind=actor
            - Find async functions: is_async=true
            - Find View structs: query=View, kind=struct
            """

            /// Search property wrappers tool description
            public static let toolSearchPropertyWrappersDescription = """
            Find Swift property wrapper usage patterns across documentation and samples. \
            Essential for discovering SwiftUI state management patterns.

            **Common wrappers:** @State, @Binding, @StateObject, @ObservedObject, @Observable, \
            @Environment, @EnvironmentObject, @Published, @AppStorage, @MainActor, @Sendable

            **Parameters:**
            - wrapper: Property wrapper name (with or without @)
            - framework: Filter by framework (optional)
            - limit: Maximum results (default 20)

            **Examples:**
            - Find @Observable usage: wrapper=Observable
            - Find @MainActor usage: wrapper=MainActor
            """

            /// Search concurrency patterns tool description
            public static let toolSearchConcurrencyDescription = """
            Find Swift concurrency patterns: async/await, actors, Sendable conformances. \
            Discover real-world concurrency usage in Apple documentation and samples.

            **Pattern options:** async, actor, sendable, mainactor, task, asyncsequence

            **Parameters:**
            - pattern: Concurrency pattern to search for
            - framework: Filter by framework (optional)
            - limit: Maximum results (default 20)

            **Examples:**
            - Find async functions: pattern=async
            - Find actor declarations: pattern=actor
            - Find Sendable types: pattern=sendable
            """

            /// Search conformances tool description
            public static let toolSearchConformancesDescription = """
            Find types by protocol conformance. Discover how protocols are implemented \
            across Apple documentation and sample code.

            **Common protocols:** View, Codable, Hashable, Equatable, Identifiable, \
            ObservableObject, Sendable, AsyncSequence, Error

            **Parameters:**
            - protocol: Protocol name to search for
            - framework: Filter by framework (optional)
            - limit: Maximum results (default 20)

            **Examples:**
            - Find View conformances: protocol=View
            - Find Sendable types: protocol=Sendable
            """

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

            /// Pause before retry after failure
            /// Rationale: Allow transient issues to resolve
            public static let retryPause: Duration = .seconds(1)
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

            /// Default maximum number of pages to crawl
            public static let defaultMaxPages = 15000

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
}
