 ---
 
 process:cupertino AND category:crawler
 
 Log all
 
 ```bash
 log stream --predicate 'subsystem == "com.docsucker.cupertino"' --info --debug
 ```
 
 ```bash
   cupertino crawl-evolution \
    --output-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution \
    --only-accepted
    ```
    
```bash
  cupertino --start-url https://developer.apple.com/documentation/swift \
    --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
    --max-pages 150000 \
    --force
```

```bash
cupertino build-index --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs --evolution-dir
  /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution --metadata-file /Volumes/Code/DeveloperExt/appledocsucker/metadata.json
  --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db
```
 
  🔍 Making Cupertino Data Searchable for AI Agents
  
  ```bash
    cupertino crawl \
    --start-url "https://developer.apple.com/documentation/swift" \
    --max-pages 10 \
    --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
    
  cupertino crawl-evolution \
    --output-dir /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution
  ```
  
    cupertino crawl \
    --start-url "https://developer.apple.com/documentation/swift" \
    --max-pages 10 \
    --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs

  This will:
  - Start from Swift documentation
  - Download 10 pages
  - Save them to /Volumes/Code/DeveloperExt/appledocsucker/docs/

  Then to build the search index:

  cupertino build-index \
    --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
    --output /Volumes/Code/DeveloperExt/appledocsucker/search.db

  And to test the MCP server with the search database:

  cupertino-mcp serve \
    --docs-dir /Volumes/Code/DeveloperExt/appledocsucker/docs \
    --search-db /Volumes/Code/DeveloperExt/appledocsucker/search.db

  You can watch the crawl progress in real-time in another terminal with:

  log stream --predicate 'subsystem == "com.docsucker.cupertino" AND category == "crawler"'

  Current State Analysis

  What Works Now (Resources Only)

  Current Flow:
  AI Agent: "Show me apple-docs://swift/array"
      ↓
  MCP Server reads exact file: ~/.docsucker/docs/swift/array.md
      ↓
  Returns full markdown content

  Limitations:
  1. ❌ Agent must know exact URI beforehand
  2. ❌ No keyword search ("show me docs about async/await")
  3. ❌ No semantic search ("how to handle errors in Swift?")
  4. ❌ Can't discover relevant docs based on query
  5. ❌ listResources() returns ALL 15,000+ pages (overwhelming)

  ---
  Recommended Solution: Add MCP Tools

  The MCP protocol supports Tools specifically for this use case! You already have the infrastructure in place but haven't implemented
  ToolProvider yet.

  Architecture: Add Search Tools

  DocsSearchToolProvider (new package)
      ↓ implements ToolProvider
  MCPServer
      ↓ registers tool provider
  AI Agent calls: search_docs("async await")
      ↓
  Returns ranked list of relevant docs with URIs
      ↓
  Agent reads specific docs using existing readResource()

  ---
  📋 Implementation Plan

  Option 1: Full-Text Search with SQLite FTS5 (Recommended)

  Why SQLite FTS5?
  - ✅ Built into Foundation (no external dependencies)
  - ✅ Fast full-text search (100x faster than regex)
  - ✅ Ranking/scoring built-in
  - ✅ Supports phrase queries, AND/OR/NOT
  - ✅ Persistent index (no rebuilding on startup)
  - ✅ ~50MB index for 15K pages

  Implementation Steps:

  Step 1: Create Search Index Package

  New Package: CupertinoSearch
  Packages/Sources/CupertinoSearch/
  ├── SearchIndex.swift          # SQLite FTS5 wrapper
  ├── SearchIndexBuilder.swift   # Builds index from crawled docs
  ├── SearchQuery.swift          # Query parser
  └── SearchResult.swift         # Ranked results

  Dependency Graph:
  CupertinoSearch → CupertinoShared (for models)
  DocsSearchToolProvider → CupertinoSearch + MCPServer
  CupertinoMCP → DocsSearchToolProvider

  Step 2: Search Index Schema

  SearchIndex.swift:
  import Foundation
  import SQLite3
  import CupertinoShared

  public actor SearchIndex {
      private var db: OpaquePointer?
      private let dbPath: URL

      public init(dbPath: URL = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".docsucker/search.db")) async throws {
          self.dbPath = dbPath
          try await openDatabase()
          try await createTables()
      }

      private func createTables() async throws {
          // FTS5 virtual table for full-text search
          let sql = """
          CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
              uri,              -- apple-docs://swift/array
              framework,        -- swift, swiftui, foundation
              title,            -- "Array"
              content,          -- full markdown content
              summary,          -- first 500 chars
              tokenize='porter unicode61'  -- Stemming + Unicode
          );

          -- Metadata table for filtering
          CREATE TABLE IF NOT EXISTS docs_metadata (
              uri TEXT PRIMARY KEY,
              framework TEXT NOT NULL,
              file_path TEXT NOT NULL,
              content_hash TEXT NOT NULL,
              last_crawled INTEGER NOT NULL,
              word_count INTEGER NOT NULL
          );

          -- Index for fast framework filtering
          CREATE INDEX IF NOT EXISTS idx_framework ON docs_metadata(framework);
          """

          var errorPointer: UnsafeMutablePointer<CChar>?
          defer { sqlite3_free(errorPointer) }

          guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
              let errorMessage = String(cString: sqlite3_errmsg(db))
              throw SearchError.sqliteError(errorMessage)
          }
      }

      // MARK: - Indexing

      public func indexDocument(
          uri: String,
          framework: String,
          title: String,
          content: String,
          filePath: String,
          contentHash: String,
          lastCrawled: Date
      ) async throws {
          // Extract summary (first 500 chars, stop at sentence)
          let summary = extractSummary(from: content)
          let wordCount = content.split(separator: " ").count

          // Insert into FTS5 table
          let ftsSql = """
          INSERT OR REPLACE INTO docs_fts (uri, framework, title, content, summary)
          VALUES (?, ?, ?, ?, ?);
          """

          var statement: OpaquePointer?
          defer { sqlite3_finalize(statement) }

          guard sqlite3_prepare_v2(db, ftsSql, -1, &statement, nil) == SQLITE_OK else {
              throw SearchError.prepareFailed
          }

          sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
          sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)
          sqlite3_bind_text(statement, 3, (title as NSString).utf8String, -1, nil)
          sqlite3_bind_text(statement, 4, (content as NSString).utf8String, -1, nil)
          sqlite3_bind_text(statement, 5, (summary as NSString).utf8String, -1, nil)

          guard sqlite3_step(statement) == SQLITE_DONE else {
              throw SearchError.insertFailed
          }

          // Insert metadata
          let metaSql = """
          INSERT OR REPLACE INTO docs_metadata
          (uri, framework, file_path, content_hash, last_crawled, word_count)
          VALUES (?, ?, ?, ?, ?, ?);
          """

          var metaStatement: OpaquePointer?
          defer { sqlite3_finalize(metaStatement) }

          sqlite3_prepare_v2(db, metaSql, -1, &metaStatement, nil)
          sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
          sqlite3_bind_text(metaStatement, 2, (framework as NSString).utf8String, -1, nil)
          sqlite3_bind_text(metaStatement, 3, (filePath as NSString).utf8String, -1, nil)
          sqlite3_bind_text(metaStatement, 4, (contentHash as NSString).utf8String, -1, nil)
          sqlite3_bind_int64(metaStatement, 5, Int64(lastCrawled.timeIntervalSince1970))
          sqlite3_bind_int(metaStatement, 6, Int32(wordCount))

          sqlite3_step(metaStatement)
      }

      // MARK: - Searching

      public func search(
          query: String,
          framework: String? = nil,
          limit: Int = 20
      ) async throws -> [SearchResult] {
          var sql = """
          SELECT
              f.uri,
              f.framework,
              f.title,
              f.summary,
              m.file_path,
              m.word_count,
              bm25(docs_fts) as rank
          FROM docs_fts f
          JOIN docs_metadata m ON f.uri = m.uri
          WHERE docs_fts MATCH ?
          """

          if framework != nil {
              sql += " AND f.framework = ?"
          }

          sql += " ORDER BY rank LIMIT ?;"

          var statement: OpaquePointer?
          defer { sqlite3_finalize(statement) }

          guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
              throw SearchError.searchFailed
          }

          // Bind parameters
          sqlite3_bind_text(statement, 1, (query as NSString).utf8String, -1, nil)

          if let framework {
              sqlite3_bind_text(statement, 2, (framework as NSString).utf8String, -1, nil)
              sqlite3_bind_int(statement, 3, Int32(limit))
          } else {
              sqlite3_bind_int(statement, 2, Int32(limit))
          }

          // Execute and collect results
          var results: [SearchResult] = []

          while sqlite3_step(statement) == SQLITE_ROW {
              let uri = String(cString: sqlite3_column_text(statement, 0))
              let framework = String(cString: sqlite3_column_text(statement, 1))
              let title = String(cString: sqlite3_column_text(statement, 2))
              let summary = String(cString: sqlite3_column_text(statement, 3))
              let filePath = String(cString: sqlite3_column_text(statement, 4))
              let wordCount = Int(sqlite3_column_int(statement, 5))
              let rank = sqlite3_column_double(statement, 6)

              results.append(SearchResult(
                  uri: uri,
                  framework: framework,
                  title: title,
                  summary: summary,
                  filePath: filePath,
                  wordCount: wordCount,
                  rank: rank
              ))
          }

          return results
      }

      private func extractSummary(from content: String, maxLength: Int = 500) -> String {
          // Remove YAML front matter
          var cleaned = content
          if let frontMatterEnd = content.range(of: "---\n", options: [], range: content.startIndex..<content.endIndex)?.upperBound {
              if let contentStart = content.range(of: "---\n", options: [], range: frontMatterEnd..<content.endIndex)?.upperBound {
                  cleaned = String(content[contentStart...])
              }
          }

          // Take first 500 chars
          let truncated = String(cleaned.prefix(maxLength))

          // Find last sentence boundary
          if let lastPeriod = truncated.lastIndex(of: ".") {
              return String(truncated[...lastPeriod])
          }

          return truncated + "..."
      }
  }

  public struct SearchResult: Codable, Sendable {
      public let uri: String
      public let framework: String
      public let title: String
      public let summary: String
      public let filePath: String
      public let wordCount: Int
      public let rank: Double  // BM25 score (lower = better match)

      public var score: Double {
          // Invert rank (FTS5 BM25 returns negative scores)
          return -rank
      }
  }

  public enum SearchError: Error, LocalizedError {
      case sqliteError(String)
      case prepareFailed
      case insertFailed
      case searchFailed

      public var errorDescription: String? {
          switch self {
          case .sqliteError(let msg): return "SQLite error: \(msg)"
          case .prepareFailed: return "Failed to prepare statement"
          case .insertFailed: return "Failed to insert document"
          case .searchFailed: return "Search query failed"
          }
      }
  }

  Step 3: Index Builder (Run After Crawl)

  SearchIndexBuilder.swift:
  import Foundation
  import CupertinoShared

  public actor SearchIndexBuilder {
      private let searchIndex: SearchIndex
      private let metadata: CrawlMetadata
      private let docsDirectory: URL

      public init(
          searchIndex: SearchIndex,
          metadata: CrawlMetadata,
          docsDirectory: URL
      ) {
          self.searchIndex = searchIndex
          self.metadata = metadata
          self.docsDirectory = docsDirectory
      }

      public func buildIndex(onProgress: ((Int, Int) -> Void)? = nil) async throws {
          print("🔨 Building search index...")

          let total = metadata.pages.count
          var processed = 0

          for (url, pageMetadata) in metadata.pages {
              // Read markdown file
              let filePath = URL(fileURLWithPath: pageMetadata.filePath)
              guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
                  continue
              }

              // Extract title from front matter or first heading
              let title = extractTitle(from: content) ?? pageMetadata.framework

              // Build URI
              let uri = "apple-docs://\(pageMetadata.framework)/\(URLUtilities.filename(from: URL(string: url)!))"

              // Index document
              try await searchIndex.indexDocument(
                  uri: uri,
                  framework: pageMetadata.framework,
                  title: title,
                  content: content,
                  filePath: pageMetadata.filePath,
                  contentHash: pageMetadata.contentHash,
                  lastCrawled: pageMetadata.lastCrawled
              )

              processed += 1

              if processed % 100 == 0 {
                  onProgress?(processed, total)
                  print("   Indexed \(processed)/\(total) documents...")
              }
          }

          print("✅ Search index built: \(processed) documents")
      }

      private func extractTitle(from markdown: String) -> String? {
          // Look for first # heading after front matter
          let lines = markdown.split(separator: "\n")
          var afterFrontMatter = false

          for line in lines {
              if line.starts(with: "---") {
                  afterFrontMatter.toggle()
                  continue
              }

              if afterFrontMatter && line.starts(with: "# ") {
                  return String(line.dropFirst(2).trimmingCharacters(in: .whitespaces))
              }
          }

          return nil
      }
  }

  Step 4: Tool Provider for Search

  DocsSearchToolProvider.swift:
  import Foundation
  import MCPServer
  import MCPShared
  import CupertinoSearch

  public actor DocsSearchToolProvider: ToolProvider {
      private let searchIndex: SearchIndex

      public init(searchIndex: SearchIndex) {
          self.searchIndex = searchIndex
      }

      // MARK: - ToolProvider

      public func listTools(cursor: String?) async throws -> ListToolsResult {
          let tools = [
              Tool(
                  name: "search_docs",
                  description: "Search Apple documentation and Swift Evolution proposals by keywords. Returns ranked list of relevant
  documents.",
                  inputSchema: JSONSchema(
                      type: "object",
                      properties: [
                          "query": AnyCodable("string"),
                          "framework": AnyCodable("string"),
                          "limit": AnyCodable("number"),
                      ],
                      required: ["query"]
                  )
              ),
              Tool(
                  name: "list_frameworks",
                  description: "List all available frameworks in the documentation index.",
                  inputSchema: JSONSchema(
                      type: "object",
                      properties: [:],
                      required: []
                  )
              ),
          ]

          return ListToolsResult(tools: tools)
      }

      public func callTool(name: String, arguments: [String: AnyCodable]?) async throws -> CallToolResult {
          switch name {
          case "search_docs":
              return try await handleSearchDocs(arguments: arguments)
          case "list_frameworks":
              return try await handleListFrameworks()
          default:
              throw ToolError.unknownTool(name)
          }
      }

      // MARK: - Tool Handlers

      private func handleSearchDocs(arguments: [String: AnyCodable]?) async throws -> CallToolResult {
          guard let query = arguments?["query"]?.value as? String else {
              throw ToolError.missingArgument("query")
          }

          let framework = arguments?["framework"]?.value as? String
          let limit = arguments?["limit"]?.value as? Int ?? 20

          // Perform search
          let results = try await searchIndex.search(
              query: query,
              framework: framework,
              limit: limit
          )

          // Format results as markdown
          var markdown = "# Search Results for \"\(query)\"\n\n"

          if framework != nil {
              markdown += "_Filtered to framework: \(framework!)_\n\n"
          }

          markdown += "Found \(results.count) results:\n\n"

          for (index, result) in results.enumerated() {
              markdown += "## \(index + 1). \(result.title)\n\n"
              markdown += "**Framework:** \(result.framework)  \n"
              markdown += "**URI:** `\(result.uri)`  \n"
              markdown += "**Score:** \(String(format: "%.2f", result.score))  \n"
              markdown += "**Summary:** \(result.summary)\n\n"
              markdown += "---\n\n"
          }

          if results.isEmpty {
              markdown += "_No results found. Try different keywords._\n"
          }

          let content = ContentBlock.text(
              TextContent(
                  type: "text",
                  text: markdown
              )
          )

          return CallToolResult(content: [content])
      }

      private func handleListFrameworks() async throws -> CallToolResult {
          let frameworks = try await searchIndex.listFrameworks()

          var markdown = "# Available Frameworks\n\n"

          for (framework, count) in frameworks.sorted(by: { $0.value > $1.value }) {
              markdown += "- **\(framework)**: \(count) pages\n"
          }

          let content = ContentBlock.text(
              TextContent(
                  type: "text",
                  text: markdown
              )
          )

          return CallToolResult(content: [content])
      }
  }

  enum ToolError: Error, LocalizedError {
      case unknownTool(String)
      case missingArgument(String)

      var errorDescription: String? {
          switch self {
          case .unknownTool(let name):
              return "Unknown tool: \(name)"
          case .missingArgument(let arg):
              return "Missing required argument: \(arg)"
          }
      }
  }

  Step 5: Update CupertinoMCP to Register Tool Provider

  CupertinoMCP/main.swift:
  @main
  struct CupertinoMCP: AsyncParsableCommand {
      @Option(name: .long, help: "Path to crawled documentation")
      var docsDir: String = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".docsucker/docs").path

      @Option(name: .long, help: "Path to search index database")
      var searchDB: String = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".docsucker/search.db").path

      func run() async throws {
          // Load configuration
          let config = CupertinoConfiguration(
              crawler: CrawlerConfiguration(
                  outputDirectory: URL(fileURLWithPath: docsDir)
              )
          )

          // Initialize search index
          let searchIndex = try await SearchIndex(
              dbPath: URL(fileURLWithPath: searchDB)
          )

          // Create MCP server
          let server = MCPServer(name: "cupertino", version: "1.0.0")

          // Register resource provider (existing)
          let resourceProvider = DocsResourceProvider(configuration: config)
          server.registerResourceProvider(resourceProvider)

          // Register tool provider (NEW!)
          let toolProvider = DocsSearchToolProvider(searchIndex: searchIndex)
          server.registerToolProvider(toolProvider)

          // Connect stdio transport
          let transport = StdioTransport()
          try await server.connect(transport)

          // Keep server running
          try await Task.sleep(for: .seconds(.max))
      }
  }

  Step 6: Add CLI Command to Build Index

  CupertinoCLI/main.swift - Add new command:
  struct BuildIndexCommand: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
          commandName: "build-index",
          abstract: "Build search index from crawled documentation"
      )

      @Option(name: .long)
      var docsDir: String = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".docsucker/docs").path

      @Option(name: .long)
      var metadataFile: String = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".docsucker/metadata.json").path

      @Option(name: .long)
      var searchDB: String = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".docsucker/search.db").path

      func run() async throws {
          print("📚 Building search index...")

          // Load metadata
          let metadataURL = URL(fileURLWithPath: metadataFile)
          let metadata = try CrawlMetadata.load(from: metadataURL)

          // Initialize search index
          let searchIndex = try await SearchIndex(
              dbPath: URL(fileURLWithPath: searchDB)
          )

          // Build index
          let builder = SearchIndexBuilder(
              searchIndex: searchIndex,
              metadata: metadata,
              docsDirectory: URL(fileURLWithPath: docsDir)
          )

          try await builder.buildIndex { processed, total in
              let percent = Double(processed) / Double(total) * 100
              print(String(format: "   Progress: %.1f%% (\(processed)/\(total))", percent))
          }

          print("✅ Search index built successfully!")
          print("📊 Index location: \(searchDB)")
      }
  }

  ---
  Usage Flow

  1. Crawl docs (existing):
  cupertino crawl --max-pages 15000

  2. Build search index (new):
  cupertino build-index
  # Output: ~/.docsucker/search.db (~50MB)

  3. Start MCP server:
  cupertino-mcp serve

  4. AI Agent searches:
  Agent: Use tool "search_docs" with query="async await concurrency"

  Response:
  # Search Results for "async await concurrency"

  Found 12 results:

  ## 1. Swift Concurrency

  **Framework:** swift
  **URI:** `apple-docs://swift/concurrency`
  **Score:** 95.42
  **Summary:** Swift provides built-in support for writing asynchronous and parallel code...

  ## 2. async/await

  **Framework:** swift
  **URI:** `apple-docs://swift/async-await`
  **Score:** 89.33
  **Summary:** The async and await keywords enable you to write asynchronous code...

  5. Agent reads specific doc:
  Agent: Read resource "apple-docs://swift/concurrency"

  Response: [Full markdown content]

  ---
  Alternative Options

  Option 2: Lightweight In-Memory Search

  Pros:
  - ✅ Zero dependencies
  - ✅ Simple implementation

  Cons:
  - ❌ Slow (regex-based)
  - ❌ No ranking
  - ❌ High memory usage (loads all docs)

  Implementation:
  public actor SimpleSearch {
      private var documents: [String: String] = [:]  // URI → content

      public func search(query: String) -> [String] {
          let keywords = query.lowercased().split(separator: " ")

          return documents.filter { uri, content in
              let lowerContent = content.lowercased()
              return keywords.allSatisfy { lowerContent.contains($0) }
          }.keys.sorted()
      }
  }

  ⚠️ Not recommended for 15K+ documents.

  ---
  Option 3: External Search Engine (Elasticsearch, Meilisearch)

  Pros:
  - ✅ Advanced features (fuzzy search, synonyms, highlights)
  - ✅ Horizontal scaling

  Cons:
  - ❌ Requires separate server process
  - ❌ Complex setup
  - ❌ Network dependency

  ⚠️ Overkill for local documentation.

  ---
  Option 4: Vector Embeddings (Semantic Search)

  Pros:
  - ✅ Understands meaning ("error handling" finds "try/catch")
  - ✅ Best for AI agents

  Cons:
  - ❌ Requires embeddings model (OpenAI API or local model)
  - ❌ High disk usage (~500MB for 15K docs)
  - ❌ Slower than FTS

  Future Enhancement:
  Could add later as search_docs_semantic tool alongside keyword search.

  ---
  📦 Package.swift Changes

  // Add new targets
  let docsuckerSearchTarget = Target.target(
      name: "CupertinoSearch",
      dependencies: ["CupertinoShared"]
  )

  let docsuckerSearchTestsTarget = Target.testTarget(
      name: "CupertinoSearchTests",
      dependencies: ["CupertinoSearch"]
  )

  let docsSearchToolProviderTarget = Target.target(
      name: "DocsSearchToolProvider",
      dependencies: [
          "MCPServer",
          "MCPShared",
          "CupertinoSearch",
      ]
  )

  // Update CupertinoMCP dependencies
  let docsuckerMCPTarget = Target.executableTarget(
      name: "CupertinoMCP",
      dependencies: [
          "MCPServer",
          "MCPTransport",
          "CupertinoShared",
          "CupertinoMCPSupport",
          "DocsSearchToolProvider",  // NEW
          .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
  )

  // Update CupertinoCLI dependencies
  let docsuckerCLITarget = Target.executableTarget(
      name: "CupertinoCLI",
      dependencies: [
          "CupertinoShared",
          "CupertinoCore",
          "CupertinoSearch",  // NEW - for build-index command
          .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
  )

  ---
  🎯 Summary & Recommendation

  Best Solution: Option 1 (SQLite FTS5)

  Why:
  1. ✅ No external dependencies (SQLite built into Foundation)
  2. ✅ Fast (100x faster than regex, handles 15K docs easily)
  3. ✅ Persistent (index survives restarts)
  4. ✅ Ranking (BM25 algorithm, industry standard)
  5. ✅ Small (~50MB index for 15K docs)
  6. ✅ Platform-appropriate (matches ExtremePackaging philosophy)

  Timeline:
  - SearchIndex.swift: ~2 hours
  - SearchIndexBuilder.swift: ~1 hour
  - DocsSearchToolProvider.swift: ~1 hour
  - CLI integration: ~30 minutes
  - Testing: ~1 hour
  - Total: ~5-6 hours

  Result:
  AI agents can now:
  1. Search: "async await concurrency" → Get ranked list of 20 docs
  2. Filter: "SwiftUI view modifiers" → Only SwiftUI framework
  3. Discover: "error handling" → Find try/catch, Result, throwing functions
  4. Browse: List all frameworks with page counts

  This transforms Cupertino from a static document store into a searchable knowledge base that AI agents can actually use effectively! 🚀




  What Gets Indexed

  1. Apple Documentation (lines 40-41)

  - All pages from ~/.docsucker/docs/
  - Uses the metadata.json file to find all crawled pages
  - Indexes framework, title, and full markdown content

  2. Swift Evolution Proposals (lines 43-46)

  - All markdown files from ~/.docsucker/swift-evolution/
  - Files matching pattern SE-*.md
  - Indexed with framework set to "swift-evolution"

⏺ Read(file_path: "/Volumes/Code/DeveloperExt/work/cupertino/Packages/Sources/CupertinoSearch/SearchIndexBuilder.swift", offset: 105,
      limit: 50)
  ⎿  Read 50 lines

⏺ Perfect! Here's the complete picture:

  🔍 What Gets Indexed & Searched

  Apple Documentation

  - Source: ~/.docsucker/docs/ + metadata.json
  - Content: All crawled Apple developer documentation pages
  - Framework Detection: From URL path (e.g., /documentation/swift/array → framework: "swift")
  - URI Format: apple-docs://swift/array
  - What's indexed: Framework, title, full markdown content, summary

  Swift Evolution Proposals

  - Source: ~/.docsucker/swift-evolution/*.md
  - Pattern: Files starting with SE- (e.g., SE-0001-*.md)
  - Framework: All tagged as "swift-evolution"
  - URI Format: swift-evolution://SE-0001
  - What's indexed: Proposal ID, title, full proposal content, summary

  Example Search Results

  When an AI agent searches for "async await", they'll get results from both sources:

  # Search Results for "async await"

  Found 15 results:

  ## 1. Swift Concurrency
  - Framework: swift
  - URI: apple-docs://swift/concurrency
  - Score: 95.42
  - Summary: Swift provides built-in support for writing asynchronous...

  ## 2. SE-0296: Async/await
  - Framework: swift-evolution
  - URI: swift-evolution://SE-0296
  - Score: 93.18
  - Summary: This proposal introduces async/await syntax to Swift...

  ## 3. async/await Keywords
  - Framework: swift
  - URI: apple-docs://swift/async-await
  - Score: 89.33
  - Summary: The async and await keywords enable you to write...

  How to Use

  1. Download both sources:

  # Apple docs
  cupertino crawl --max-pages 15000

  # Swift Evolution proposals
  cupertino crawl-evolution

  2. Build unified search index:

  cupertino build-index
  # Automatically indexes both if they exist

  3. Search across both:

  # AI agent searches
  search_docs(query: "async await")
  → Returns results from BOTH Apple docs AND Evolution proposals

  # Filter to just proposals
  search_docs(query: "async await", framework: "swift-evolution")
  → Returns only Evolution proposals

  # Filter to just Apple docs
  search_docs(query: "async await", framework: "swift")
  → Returns only official Swift documentation

  Benefits

  ✅ Unified Search: One query searches both official docs and proposals✅ Framework Filtering: Can filter to just proposals or just docs✅
   Historical Context: Evolution proposals explain why features exist✅ Comprehensive: Official docs + design rationale in one place

  So yes - it searches everything you've downloaded: Apple documentation, Swift Evolution proposals, and can even search both
  simultaneously! 🎯

> how will the agent know what to do with the search results, is there some kind of result the mcp server needs to serve

⏺ Great question! Let me explain how the MCP protocol works and show you what the agent actually receives.

⏺ Read(file_path: "/Volumes/Code/DeveloperExt/work/cupertino/Packages/Sources/DocsSearchToolProvider/DocsSearchToolProvider.swift",
      offset: 60, limit: 80)
  ⎿  Read 80 lines

⏺ Perfect! Let me explain how the MCP protocol teaches the AI agent what to do:

  🎯 How AI Agents Learn What To Do

  1. Tool Discovery (Automatic)

  When the agent connects to the MCP server, it automatically calls tools/list and receives:

  {
    "tools": [
      {
        "name": "search_docs",
        "description": "Search Apple documentation and Swift Evolution proposals by keywords. Returns a ranked list of relevant documents
  with URIs that can be read using resources/read.",
        "inputSchema": {
          "type": "object",
          "required": ["query"]
        }
      },
      {
        "name": "list_frameworks",
        "description": "List all available frameworks in the documentation index with document counts. Useful for discovering what
  documentation is available.",
        "inputSchema": {
          "type": "object",
          "required": []
        }
      }
    ]
  }

  The description tells the agent what the tool does and crucially mentions "can be read using resources/read" - this is the instruction!

  2. Tool Result Format (Structured Markdown)

  When the agent calls search_docs, it receives formatted markdown with clear structure:

  # Search Results for "async await"

  Found 12 results:

  ## 1. Swift Concurrency

  - **Framework:** `swift`
  - **URI:** `apple-docs://swift/concurrency`  ← The agent sees this!
  - **Score:** 95.42
  - **Words:** 2431

  Swift provides built-in support for writing asynchronous and parallel code...

  ---

  ## 2. async/await Keywords

  - **Framework:** `swift`
  - **URI:** `apple-docs://swift/async-await`  ← And this!
  - **Score:** 89.33
  - **Words:** 892

  The async and await keywords enable you to write asynchronous code...

  💡 **Tip:** Use `resources/read` with the URI to get the full document content.

  3. The Critical Instruction (Line 107)

  Look at line 107 in the code:
  markdown += "💡 **Tip:** Use `resources/read` with the URI to get the full document content.\n"

  This explicitly tells the agent what to do next! The agent reads this and understands:
  1. I got URIs in the search results
  2. I should use resources/read to get full content
  3. The URI is apple-docs://swift/concurrency

  4. How The Agent Uses It

  Here's the actual flow:

  User: "How do I use async/await in Swift?"

  Agent Internal Process:
  ┌─────────────────────────────────────────────────┐
  │ 1. Agent sees it has access to search_docs tool │
  │    (from tool discovery)                        │
  └─────────────────────────────────────────────────┘
             ↓
  ┌─────────────────────────────────────────────────┐
  │ 2. Agent calls: search_docs                     │
  │    { query: "async await" }                     │
  └─────────────────────────────────────────────────┘
             ↓
  ┌─────────────────────────────────────────────────┐
  │ 3. Agent receives markdown with URIs:           │
  │    - apple-docs://swift/concurrency             │
  │    - apple-docs://swift/async-await             │
  │    Plus the tip: "Use resources/read..."        │
  └─────────────────────────────────────────────────┘
             ↓
  ┌─────────────────────────────────────────────────┐
  │ 4. Agent reads the tip and URIs, then calls:    │
  │    resources/read                               │
  │    { uri: "apple-docs://swift/concurrency" }    │
  └─────────────────────────────────────────────────┘
             ↓
  ┌─────────────────────────────────────────────────┐
  │ 5. Agent receives FULL markdown content         │
  │    (entire documentation page)                  │
  └─────────────────────────────────────────────────┘
             ↓
  ┌─────────────────────────────────────────────────┐
  │ 6. Agent synthesizes answer from full content   │
  │    and responds to user                         │
  └─────────────────────────────────────────────────┘

  🔗 The Two-Step Pattern

  This is a standard MCP pattern for large datasets:

  Step 1: Discovery Tool (search_docs)

  - Returns metadata (titles, URIs, summaries, scores)
  - Lightweight response
  - Agent picks the most relevant items

  Step 2: Retrieval Resource (resources/read)

  - Returns full content (complete markdown)
  - Heavy response
  - Agent only fetches what it needs

  📋 Example Real Interaction

  Let me show you what Claude Desktop would actually see:

  User: "Show me documentation about async/await"

  Claude thinks: I have a search_docs tool, let me use it

  [Claude calls tool]
  Tool: search_docs
  Arguments: { "query": "async await" }

  [MCP server responds with markdown]
  # Search Results for "async await"

  Found 3 results:

  ## 1. Swift Concurrency
  - **Framework:** `swift`
  - **URI:** `apple-docs://swift/concurrency`
  - **Score:** 95.42

  Swift provides built-in support for writing asynchronous...

  💡 **Tip:** Use `resources/read` with the URI to get the full document content.

  Claude thinks: Great! I found relevant docs. The URI is apple-docs://swift/concurrency.
  The tip says I should use resources/read. Let me fetch the full content.

  [Claude calls resource]
  Resource: resources/read
  Arguments: { "uri": "apple-docs://swift/concurrency" }

  [MCP server responds with full markdown]
  ---
  source: https://developer.apple.com/documentation/swift/concurrency
  ---

  # Swift Concurrency

  Swift provides built-in support for writing asynchronous and parallel code in a structured way...

  [Full 5000-word documentation page]

  Claude: [Reads entire page, synthesizes answer]

  Response to user: "Here's how async/await works in Swift..."

  🎓 Why This Design?

  Without Search (Before)

  Agent: "I need docs about async/await"
  Problem: Must know exact URI or list 15,000 resources
  Result: ❌ Can't find it

  With Search (After)

  Agent: "I need docs about async/await"
  Step 1: search_docs → Get ranked URIs
  Step 2: resources/read → Get full content
  Result: ✅ Finds and reads exactly what's needed

  🔑 Key Design Elements

  1. Tool Description (Lines 22-25)

  description: """
  Search Apple documentation and Swift Evolution proposals by keywords. \
  Returns a ranked list of relevant documents with URIs that can be read using resources/read.
  """
  → This tells the agent the tool's purpose and next step

  2. Structured Output (Lines 90-94)

  markdown += "- **Framework:** `\(result.framework)`\n"
  markdown += "- **URI:** `\(result.uri)`\n"  // ← Clearly labeled!
  markdown += "- **Score:** \(String(format: "%.2f", result.score))\n"
  → The agent can parse the markdown and extract URIs

  3. Explicit Instruction (Line 107)

  markdown += "💡 **Tip:** Use `resources/read` with the URI to get the full document content.\n"
  → This is a direct instruction to the agent

  4. Contextual Summary (Lines 96-97)

  markdown += result.summary
  → The agent can decide if the full doc is worth reading

  Summary

  The agent knows what to do because:

  1. ✅ Tool description explains the workflow
  2. ✅ Structured output makes URIs easy to extract
  3. ✅ Explicit tip instructs the next step
  4. ✅ Standard MCP pattern (search → read) that AI models are trained on
  5. ✅ Contextual summaries help agent decide what to fetch

  The MCP protocol is designed for this two-step dance:
  - Tools for discovery/actions (search, filter, analyze)
  - Resources for retrieval (read full content)

  Your implementation follows this pattern perfectly! 🎯

