# AppleCupertino GUI Proposal

## Executive Summary

This document proposes a native macOS GUI application for AppleCupertino that reuses the existing Swift codebase, provides bidirectional CLI ↔ GUI control, and enhances the user experience for documentation crawling, indexing, and search.

## Current State

**What we have:**
- `cupertino` CLI tool for crawling Apple documentation
- `cupertino-mcp` MCP server for AI agent integration
- `cupertino build-index` for building search indices
- Modular Swift packages: Core, Search, MCP, Logging

**What's missing:**
- Visual progress monitoring during long crawls
- Easy configuration without remembering CLI flags
- Quick access to search without terminal
- Status overview of indexed content
- User-friendly interface for non-technical users

## Goals

### Primary Goals
1. **Reuse existing code** - No duplication, direct package imports
2. **Bidirectional control** - CLI can control GUI, GUI can launch CLI operations
3. **Real-time monitoring** - Live progress updates during crawls
4. **Native macOS experience** - SwiftUI, follows platform conventions
5. **Backwards compatible** - CLI remains fully functional

### Secondary Goals
- Visual search interface with syntax highlighting
- Database statistics dashboard
- Sample code browser
- Framework coverage visualization
- Export capabilities (PDF, HTML, etc.)

## Architecture

### High-Level Structure

```
cupertino/
├── Sources/
│   ├── CupertinoCore/          # Shared crawling logic (existing)
│   ├── CupertinoSearch/        # Shared search indexing (existing)
│   ├── CupertinoLogging/       # Shared logging (existing)
│   ├── CupertinoMCP/           # MCP server (existing)
│   ├── CupertinoCLI/           # CLI executable (existing)
│   ├── CupertinoService/       # XPC service for IPC (new, optional)
│   └── CupertinoGUI/           # SwiftUI app (new)
└── AppleCupertino.xcodeproj    # Xcode project (new, optional)
```

### Component Breakdown

#### 1. CupertinoShared (New Package)

**Purpose:** Shared state management and models for both CLI and GUI

```swift
public actor CrawlState: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var currentPage: Int = 0
    @Published public private(set) var totalPages: Int = 0
    @Published public private(set) var currentURL: String = ""
    @Published public private(set) var errors: [CrawlError] = []
    @Published public private(set) var recentPages: [PageInfo] = []

    public func update(currentPage: Int, url: String) async {
        self.currentPage = currentPage
        self.currentURL = url
    }
}

public struct CrawlConfiguration: Codable {
    public let startURL: String
    public let outputDirectory: String
    public let maxPages: Int
    public let maxDepth: Int?
    public let respectRobots: Bool
}

public struct IndexStatistics: Codable {
    public let totalDocuments: Int
    public let totalWords: Int
    public let frameworks: [String: Int]
    public let lastUpdated: Date
    public let databaseSize: Int64
}
```

#### 2. CupertinoService (New Package)

**Purpose:** XPC service for inter-process communication

```swift
import Foundation

@objc public protocol CrawlerServiceProtocol {
    func startCrawl(
        config: Data,  // Encoded CrawlConfiguration
        reply: @escaping (Result<Void, Error>) -> Void
    )

    func stopCrawl(reply: @escaping () -> Void)

    func getCrawlStatus(reply: @escaping (Data?) -> Void)  // Encoded CrawlState

    func buildIndex(
        docsDir: String,
        evolutionDir: String,
        samplesDir: String?,
        dbPath: String,
        reply: @escaping (Result<Data, Error>) -> Void  // Encoded IndexStatistics
    )

    func searchDocs(
        query: String,
        limit: Int,
        reply: @escaping (Result<Data, Error>) -> Void  // Encoded [SearchResult]
    )
}

public class CrawlerService: NSObject, CrawlerServiceProtocol {
    private var currentCrawler: WebCrawler?
    private let crawlState = CrawlState()

    public func startCrawl(
        config: Data,
        reply: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                let crawlConfig = try JSONDecoder().decode(
                    CrawlConfiguration.self,
                    from: config
                )

                let crawler = WebCrawler(
                    configuration: /* convert crawlConfig */
                )

                self.currentCrawler = crawler
                await self.crawlState.update(isRunning: true)

                await crawler.crawl(
                    startURL: URL(string: crawlConfig.startURL)!,
                    maxPages: crawlConfig.maxPages
                )

                reply(.success(()))
            } catch {
                reply(.failure(error))
            }
        }
    }

    // ... other implementations
}
```

#### 3. CupertinoGUI (New Package)

**Purpose:** Native macOS SwiftUI application

**Key Views:**

##### Main Window (Tab-based)
```swift
import SwiftUI
import CupertinoShared

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        TabView {
            CrawlerView()
                .tabItem {
                    Label("Crawl", systemImage: "arrow.down.doc")
                }

            IndexView()
                .tabItem {
                    Label("Index", systemImage: "square.grid.3x3")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            StatsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar")
                }
        }
        .frame(minWidth: 800, minHeight: 600)
        .environmentObject(appState)
    }
}
```

##### Crawler View
```swift
struct CrawlerView: View {
    @StateObject private var crawlerVM = CrawlerViewModel()
    @State private var startURL = "https://developer.apple.com/documentation/swift"
    @State private var outputDir = "/Volumes/Code/DeveloperExt/appledocsucker/docs"
    @State private var maxPages = 150000

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Configuration Section
            GroupBox("Crawl Configuration") {
                Form {
                    TextField("Start URL:", text: $startURL)

                    HStack {
                        TextField("Output Directory:", text: $outputDir)
                        Button("Browse...") {
                            // Show directory picker
                        }
                    }

                    Stepper("Max Pages: \(maxPages)", value: $maxPages, in: 1...200000)
                }
                .padding()
            }

            // Progress Section
            if crawlerVM.isRunning {
                GroupBox("Progress") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pages:")
                            Spacer()
                            Text("\(crawlerVM.currentPage) / \(maxPages)")
                                .foregroundColor(.secondary)
                        }

                        ProgressView(value: crawlerVM.progress)

                        HStack {
                            Text("Current:")
                            Spacer()
                            Text(crawlerVM.currentURL)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Rate:")
                            Spacer()
                            Text("\(crawlerVM.pagesPerHour, specifier: "%.0f") pages/hour")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("ETA:")
                            Spacer()
                            Text(crawlerVM.estimatedCompletion)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }

            // Recent Pages Section
            if !crawlerVM.recentPages.isEmpty {
                GroupBox("Recent Pages") {
                    List(crawlerVM.recentPages) { page in
                        HStack {
                            Image(systemName: page.isNew ? "doc.badge.plus" : "arrow.triangle.2.circlepath")
                                .foregroundColor(page.isNew ? .green : .orange)
                            VStack(alignment: .leading) {
                                Text(page.title)
                                    .font(.headline)
                                Text(page.framework)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(page.size)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 200)
                }
            }

            // Control Buttons
            HStack {
                if crawlerVM.isRunning {
                    Button("Stop", role: .destructive) {
                        crawlerVM.stopCrawl()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Crawl") {
                        crawlerVM.startCrawl(
                            url: startURL,
                            outputDir: outputDir,
                            maxPages: maxPages
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("View Logs") {
                    crawlerVM.showLogs()
                }
            }

            Spacer()
        }
        .padding()
    }
}
```

##### Search View
```swift
struct SearchView: View {
    @StateObject private var searchVM = SearchViewModel()
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search documentation...", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchVM.search(query: query)
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        searchVM.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Results List
            if searchVM.isSearching {
                ProgressView("Searching...")
                    .frame(maxHeight: .infinity)
            } else if searchVM.results.isEmpty && !query.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No results found for '\(query)'")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(searchVM.results) { result in
                    SearchResultRow(result: result)
                        .onTapGesture {
                            searchVM.openResult(result)
                        }
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.title)
                    .font(.headline)
                Spacer()
                Text(result.framework)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }

            Text(result.summary)
                .font(.body)
                .lineLimit(2)
                .foregroundColor(.secondary)

            HStack {
                Label("\(result.wordCount) words", systemImage: "text.alignleft")
                Spacer()
                Text("Relevance: \(result.rank, specifier: "%.2f")")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

##### Statistics View
```swift
struct StatsView: View {
    @StateObject private var statsVM = StatsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Overview Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        title: "Total Documents",
                        value: "\(statsVM.stats.totalDocuments)",
                        icon: "doc.text",
                        color: .blue
                    )

                    StatCard(
                        title: "Total Words",
                        value: statsVM.stats.totalWords.formatted(),
                        icon: "textformat.abc",
                        color: .green
                    )

                    StatCard(
                        title: "Frameworks",
                        value: "\(statsVM.stats.frameworks.count)",
                        icon: "square.stack.3d.up",
                        color: .orange
                    )
                }

                // Framework Breakdown Chart
                GroupBox("Framework Coverage") {
                    Chart(statsVM.frameworkData) { item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Framework", item.name)
                        )
                        .foregroundStyle(by: .value("Type", item.type))
                    }
                    .frame(height: 400)
                    .padding()
                }

                // Database Info
                GroupBox("Database Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Size", value: statsVM.stats.databaseSize.formatted(.byteCount(style: .file)))
                        InfoRow(label: "Last Updated", value: statsVM.stats.lastUpdated.formatted())
                        InfoRow(label: "Location", value: statsVM.dbPath)
                    }
                    .padding()
                }
            }
            .padding()
        }
        .onAppear {
            statsVM.loadStats()
        }
    }
}
```

### View Models

```swift
@MainActor
class CrawlerViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var currentPage = 0
    @Published var currentURL = ""
    @Published var progress: Double = 0
    @Published var recentPages: [PageInfo] = []
    @Published var pagesPerHour: Double = 0
    @Published var estimatedCompletion = ""

    private var service: CrawlerServiceProtocol?
    private var statusTimer: Timer?

    func startCrawl(url: String, outputDir: String, maxPages: Int) {
        let config = CrawlConfiguration(
            startURL: url,
            outputDirectory: outputDir,
            maxPages: maxPages,
            maxDepth: nil,
            respectRobots: true
        )

        Task {
            let configData = try JSONEncoder().encode(config)

            service?.startCrawl(config: configData) { result in
                switch result {
                case .success:
                    print("Crawl started successfully")
                case .failure(let error):
                    print("Crawl failed: \(error)")
                }
            }

            startStatusUpdates()
        }
    }

    private func startStatusUpdates() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func updateStatus() {
        service?.getCrawlStatus { statusData in
            guard let data = statusData,
                  let state = try? JSONDecoder().decode(CrawlState.self, from: data) else {
                return
            }

            Task { @MainActor in
                self.isRunning = state.isRunning
                self.currentPage = state.currentPage
                self.currentURL = state.currentURL
                self.progress = Double(state.currentPage) / Double(state.totalPages)
                self.recentPages = state.recentPages
                // Calculate rate and ETA
            }
        }
    }

    func stopCrawl() {
        service?.stopCrawl {
            Task { @MainActor in
                self.isRunning = false
                self.statusTimer?.invalidate()
            }
        }
    }
}
```

## CLI ↔ GUI Integration

### Approach: XPC Service as Bridge

Both CLI and GUI communicate through the same XPC service:

```
┌─────────┐          ┌──────────────┐          ┌─────────┐
│   CLI   │ ────────▶│ XPC Service  │◀──────── │   GUI   │
└─────────┘          └──────────────┘          └─────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │ Shared State │
                     │  (Actor)     │
                     └──────────────┘
```

### CLI Commands with GUI Control

```bash
# Start GUI from CLI
cupertino gui show

# Start crawl that GUI can monitor
cupertino crawl --start-url ... --gui-attach

# Query GUI status from CLI
cupertino gui status

# Open search in GUI with query
cupertino gui search "URLSession"
```

### Implementation

```swift
// In CLI
struct GUICommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "gui",
        abstract: "Control GUI application"
    )

    @Flag(name: .long, help: "Show GUI window")
    var show = false

    @Flag(name: .long, help: "Get GUI status")
    var status = false

    @Option(name: .long, help: "Open search with query")
    var search: String?

    func run() async throws {
        let connection = NSXPCConnection(serviceName: "com.docsucker.service")
        connection.remoteObjectInterface = NSXPCInterface(with: CrawlerServiceProtocol.self)
        connection.resume()

        if show {
            // Activate GUI application
            NSWorkspace.shared.launchApplication(
                withBundleIdentifier: "com.docsucker.gui",
                options: [.default],
                additionalEventParamDescriptor: nil,
                launchIdentifier: nil
            )
        }

        if status {
            // Query and print status
        }

        if let query = search {
            // Send search command to GUI
        }
    }
}
```

## Deployment

### Build Targets

1. **CLI Binary** - `/usr/local/bin/cupertino` (existing)
2. **XPC Service** - `/Library/Application Support/AppleCupertino/service.xpc`
3. **GUI App** - `/Applications/AppleCupertino.app`

### Installation

```bash
# Via Homebrew (updated formula)
brew install cupertino

# Installs:
# - CLI binary
# - XPC service
# - GUI app (optional)

# GUI-only users can download .dmg
# Includes bundled CLI and service
```

## Implementation Phases

### Realistic Estimates (Experienced Swift Developer)

**Total: ~6-8 hours** for working GUI with basic features

### Phase 1: Basic GUI (2-4 hours)
- [ ] Create CupertinoGUI SwiftUI app target
- [ ] Import existing CupertinoCore, CupertinoSearch packages
- [ ] Implement CrawlerView with live progress (using existing Crawler)
- [ ] Implement basic SearchView (using existing SearchIndex)
- [ ] Implement StatsView with database info

### Phase 2: Polish & Features (2-3 hours)
- [ ] Add preferences/settings panel
- [ ] Improve UI/UX with better layouts
- [ ] Add error handling and user feedback
- [ ] Basic testing

### Phase 3: CLI Integration (1-2 hours, optional)
- [ ] Add `gui` subcommand to CLI
- [ ] Implement XPC service for bidirectional control (if needed)
- [ ] Or: Simple shared state file approach

### Phase 4: Distribution (1 hour)
- [ ] Create .dmg for GUI app
- [ ] Update documentation

---

### Professional Billable Estimates (Client Project)

**Total: 40-60 hours** including meetings, documentation, and buffer

This accounts for:
- Client meetings and requirements gathering (4-6 hours)
- Architecture planning and approval cycles (4-6 hours)
- Implementation with production-quality code (16-24 hours)
- Code review iterations (4-6 hours)
- Comprehensive testing and QA (6-8 hours)
- Documentation and handoff (4-6 hours)
- Buffer for unexpected issues (15-20%)

**Breakdown:**

#### Phase 1: Planning & Architecture (8-12 hours)
- [ ] Requirements gathering meeting
- [ ] Technical architecture document
- [ ] UI/UX mockups and approval
- [ ] Project setup and scaffolding

#### Phase 2: Core Implementation (16-24 hours)
- [ ] Create CupertinoGUI SwiftUI app
- [ ] Implement CrawlerView with live progress
- [ ] Implement SearchView with results display
- [ ] Implement StatsView with charts and metrics
- [ ] Implement Settings/Preferences

#### Phase 3: Advanced Features (8-12 hours)
- [ ] XPC service for CLI ↔ GUI communication
- [ ] Sample code browser integration
- [ ] Export capabilities (PDF, HTML)
- [ ] Framework coverage visualization
- [ ] Keyboard shortcuts and accessibility

#### Phase 4: Testing & Polish (6-8 hours)
- [ ] Unit tests for view models
- [ ] Integration tests
- [ ] UI tests
- [ ] Performance optimization
- [ ] Bug fixes

#### Phase 5: Distribution & Documentation (4-6 hours)
- [ ] Update Homebrew formula
- [ ] Create .dmg installer
- [ ] Write user guide
- [ ] Create demo video
- [ ] Client handoff meeting

---

### Reality vs. Billing

| Task | Realistic Time | Billable Time | Reason for Difference |
|------|----------------|---------------|----------------------|
| Basic GUI setup | 30 min | 4 hours | Meetings, requirements, project setup |
| CrawlerView | 1 hour | 6 hours | Mockup approval, iterations, polish |
| SearchView | 1 hour | 6 hours | UI/UX feedback cycles |
| StatsView | 1 hour | 6 hours | Chart library selection, client approval |
| CLI Integration | 1 hour | 8 hours | Architecture review, security considerations |
| Testing | 30 min | 6 hours | QA process, bug tracking, fixes |
| Distribution | 1 hour | 4 hours | Installer testing, documentation |
| Buffer | - | 8-12 hours | Unknown unknowns, scope creep |

**Key Insight:** The code takes 6-8 hours. The professional process takes 40-60 hours.

## Technical Considerations

### State Management

**Challenge:** Keeping CLI and GUI state synchronized

**Solution:** Single source of truth in XPC service

```swift
actor SharedCrawlState {
    private var listeners: [UUID: AsyncStream<CrawlState>.Continuation] = [:]

    func subscribe() -> AsyncStream<CrawlState> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.unsubscribe(id: id)
                }
            }
        }
    }

    func update(state: CrawlState) {
        for continuation in listeners.values {
            continuation.yield(state)
        }
    }
}
```

### Performance

**Challenge:** Real-time updates don't slow down crawl

**Solution:**
- Throttle GUI updates to 1-2 per second
- Use background threads for status queries
- Actor isolation prevents data races

```swift
actor ThrottledPublisher {
    private var lastUpdate = Date.distantPast
    private let minimumInterval: TimeInterval = 0.5

    func shouldPublish() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastUpdate) >= minimumInterval {
            lastUpdate = now
            return true
        }
        return false
    }
}
```

### Testing

**Unit Tests:**
- All existing tests continue to work
- New tests for view models
- XPC communication tests

**Integration Tests:**
- CLI commands with GUI running
- GUI operations triggering CLI actions
- State synchronization tests

**UI Tests:**
- SwiftUI view tests
- User interaction flows
- Accessibility tests

## Open Questions

1. **Should GUI bundle its own database viewer?**
   - Pro: Users can explore SQLite directly
   - Con: Adds complexity, might confuse non-technical users

2. **Real-time log viewer in GUI?**
   - Pro: Easier debugging
   - Con: os.log already works well with Console.app

3. **Support for multiple concurrent crawls?**
   - Pro: Power users might want this
   - Con: Significantly complicates state management

4. **Web-based alternative?**
   - Pro: Cross-platform, remote access
   - Con: More complex architecture, security concerns

5. **Integration with Xcode?**
   - Could be an Xcode source editor extension
   - Quick access to search from IDE

## Success Metrics

**Adoption:**
- 50% of Homebrew installs also use GUI within 3 months
- Positive feedback on ease of use

**Performance:**
- GUI updates don't slow crawl by more than 5%
- Search results render in < 100ms

**Reliability:**
- Zero crashes in production after 1 month
- CLI and GUI state always synchronized

## Conclusion

A native macOS GUI for AppleCupertino will:
1. Make the tool accessible to more users
2. Provide better visibility into long-running operations
3. Maintain full backwards compatibility with CLI
4. Leverage existing Swift code without duplication
5. Enable rich visualizations and analytics

The XPC-based architecture ensures both CLI and GUI can coexist and control the same underlying operations, providing flexibility for different workflows.

**Recommendation:** Proceed with Phase 1 (Foundation) to validate the architecture before committing to full GUI development.
