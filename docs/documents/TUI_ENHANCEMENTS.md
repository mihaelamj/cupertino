# TUI Enhancements & Roadmap

This document tracks enhancements and improvements for the Cupertino TUI (Terminal User Interface) package curator.

## Current Status (2025-11-19)

**Version**: 1.0
**Test Coverage**: 63 comprehensive tests
**Lines of Code**: ~2,000 (main event loop: 500 lines)
**Features**: Multi-view architecture (Home, Packages, Library, Settings)

### Recently Completed ✅
- Multi-view navigation system
- Persistent configuration (ConfigManager)
- Paste support for path input (cmd+v)
- Download status tracking (📦 indicator)
- Library artifact viewing
- Settings editor with live reload
- Comprehensive test suite

---

## Priority 1 - Immediate Enhancements

### 1.1 Help Screen
**Goal**: Add contextual help accessible via `?` key

**Design**:
```
┌──────────────────────────────────────────────────────────────────────┐
│                        Cupertino TUI - Help                          │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Navigation:                                                          │
│   ↑↓ / j/k    Move cursor up/down                                  │
│   PgUp/PgDn   Jump by page                                          │
│   Home/End    Jump to start/end                                     │
│   h / Esc     Return to home                                        │
│   1-3         Quick jump to view                                    │
│                                                                      │
│ Package Management:                                                  │
│   Space       Toggle package selection                              │
│   w           Save selections to priority list                      │
│   o / Enter   Open package in browser                               │
│                                                                      │
│ Filtering & Search:                                                  │
│   f           Cycle filter (All/Selected/Downloaded)                │
│   s           Cycle sort (Stars/Name/Recent)                        │
│   /           Enter search mode                                     │
│                                                                      │
│ Settings:                                                            │
│   e           Edit (when in settings)                               │
│                                                                      │
│ General:                                                             │
│   ?           Show this help                                        │
│   q / Ctrl+C  Quit application                                      │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│ Press any key to close                                               │
└──────────────────────────────────────────────────────────────────────┘
```

**Implementation Tasks**:
- [ ] Create `HelpView.swift` with keybinding legend
- [ ] Add `ViewMode.help` case to AppState
- [ ] Handle `?` key in all views to show help
- [ ] Add "Press ? for help" hint in footers
- [ ] Test help screen rendering at different terminal sizes

**Files to Modify**:
- `Sources/TUI/Views/HelpView.swift` (new)
- `Sources/TUI/Models/AppState.swift` (add .help to ViewMode)
- `Sources/TUI/PackageCurator.swift` (handle ? key)
- `Tests/TUITests/ViewTests.swift` (add HelpView tests)

**Estimated Effort**: 2-3 hours

---

### 1.2 Progress Indicators
**Goal**: Show visual feedback for long-running operations

**Current Issues**:
- Artifact scanning blocks UI (no feedback)
- Saving selections appears frozen
- No indication of operation progress

**Design Options**:

**Option A - Simple Spinner**:
```
Scanning library artifacts... ⠋
```

**Option B - Progress Bar**:
```
Scanning artifacts: [████████████        ] 60% (3/5 directories)
```

**Option C - Status Line**:
```
│ Status: Scanning Apple Documentation... (1.2 GB, 15,234 files)     │
```

**Recommended**: Option A (spinner) for simplicity

**Implementation Tasks**:
- [ ] Create `Spinner.swift` with animation frames (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏)
- [ ] Add async progress tracking to artifact scanner
- [ ] Show spinner during file I/O operations
- [ ] Add status message area in views
- [ ] Test spinner doesn't interfere with input

**Files to Modify**:
- `Sources/TUI/Infrastructure/Spinner.swift` (new)
- `Sources/TUI/PackageCurator.swift` (add progress feedback)
- `Sources/TUI/Views/*.swift` (add status area)
- `Tests/TUITests/InfrastructureTests.swift` (spinner tests)

**Estimated Effort**: 3-4 hours

---

### 1.3 Refactor PackageCurator Event Loop
**Goal**: Break down 500-line main loop into smaller, testable components

**Current Architecture**:
```
PackageCurator.run()
  ├─ 500-line switch statement
  ├─ View mode handling
  ├─ Input processing
  ├─ State mutations
  └─ Rendering logic
```

**Proposed Architecture**:
```
PackageCurator
  ├─ ViewRouter (handles view transitions)
  ├─ InputHandler (processes keyboard input)
  ├─ RenderEngine (manages screen updates)
  └─ StateManager (coordinates state changes)
```

**Design**:

```swift
// ViewRouter.swift
actor ViewRouter {
    func route(_ key: Key, state: AppState) -> ViewTransition?
    func handleViewChange(_ transition: ViewTransition, state: AppState)
}

// InputHandler.swift
struct InputHandler {
    func handleInput(_ key: Key, viewMode: ViewMode, state: AppState) -> InputAction
}

// RenderEngine.swift
actor RenderEngine {
    func render(viewMode: ViewMode, state: AppState, screen: Screen) async
    func needsRedraw(oldState: AppState, newState: AppState) -> Bool
}
```

**Implementation Tasks**:
- [ ] Design router/handler interfaces
- [ ] Extract view routing logic into ViewRouter
- [ ] Extract input handling into InputHandler
- [ ] Extract rendering logic into RenderEngine
- [ ] Update PackageCurator to use new components
- [ ] Add comprehensive tests for each component
- [ ] Ensure no behavioral changes (refactor only)

**Files to Create**:
- `Sources/TUI/Routing/ViewRouter.swift`
- `Sources/TUI/Routing/InputHandler.swift`
- `Sources/TUI/Routing/RenderEngine.swift`
- `Tests/TUITests/RoutingTests.swift`

**Files to Modify**:
- `Sources/TUI/PackageCurator.swift` (simplify to use router)
- `Sources/TUI/Models/AppState.swift` (if needed)

**Estimated Effort**: 6-8 hours

---

### 1.4 Package Details View
**Goal**: Show comprehensive package information

**Design**:
```
┌──────────────────────────────────────────────────────────────────────┐
│                    Package Details - vapor/vapor                     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Repository:  https://github.com/vapor/vapor                         │
│ Stars:       ⭐ 22,345                                               │
│ Language:    Swift                                                   │
│ License:     MIT                                                     │
│ Updated:     2025-11-15                                             │
│ Selected:    [★] Priority package                                   │
│ Downloaded:  📦 Available locally                                    │
│                                                                      │
│ Description:                                                         │
│   A server-side Swift HTTP web framework.                          │
│                                                                      │
│ Topics:                                                              │
│   swift, server, http, web-framework, vapor                         │
│                                                                      │
│ Dependencies: (if available)                                         │
│   • swift-nio                                                       │
│   • swift-log                                                       │
│   • swift-crypto                                                    │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│ Enter:Open  Space:Toggle  Esc:Back  q:Quit                          │
└──────────────────────────────────────────────────────────────────────┘
```

**Implementation Tasks**:
- [ ] Create `PackageDetailsView.swift`
- [ ] Add `ViewMode.packageDetails(PackageEntry)` to AppState
- [ ] Handle Enter/Return key in package list to show details
- [ ] Implement word wrapping for description
- [ ] Add tests for details view rendering

**Files to Create**:
- `Sources/TUI/Views/PackageDetailsView.swift`
- `Tests/TUITests/PackageDetailsViewTests.swift`

**Files to Modify**:
- `Sources/TUI/Models/AppState.swift` (add details view mode)
- `Sources/TUI/PackageCurator.swift` (handle navigation)

**Estimated Effort**: 4-5 hours

---

### 1.5 Confirmation Dialogs
**Goal**: Prevent accidental destructive operations

**Use Cases**:
- Saving selections (overwrite existing priority-packages.json)
- Clearing all selections
- Changing base directory (data may be lost)

**Design**:
```
┌────────────────────────────────────────────┐
│            Confirm Action                  │
├────────────────────────────────────────────┤
│                                            │
│  Save 42 selected packages?                │
│                                            │
│  This will overwrite:                      │
│  priority-packages.json                    │
│                                            │
│  [Y] Yes, save    [N] Cancel               │
│                                            │
└────────────────────────────────────────────┘
```

**Implementation Tasks**:
- [ ] Create `ConfirmDialog.swift` component
- [ ] Add dialog rendering overlay
- [ ] Handle Y/N input for confirmation
- [ ] Add confirmation before overwrite operations
- [ ] Test dialog rendering and input handling

**Files to Create**:
- `Sources/TUI/Components/ConfirmDialog.swift`
- `Tests/TUITests/ConfirmDialogTests.swift`

**Files to Modify**:
- `Sources/TUI/PackageCurator.swift` (add confirmation prompts)
- `Sources/TUI/Models/AppState.swift` (track dialog state)

**Estimated Effort**: 3-4 hours

---

## Priority 2 - Short-term Features

### 2.1 Bulk Operations
- [ ] Select all filtered packages
- [ ] Clear all selections
- [ ] Invert selection
- [ ] Select by criteria (stars > N, language, etc.)

**Keybindings**:
- `Ctrl+A` - Select all visible
- `Ctrl+D` - Deselect all
- `Ctrl+I` - Invert selection

**Estimated Effort**: 4-5 hours

---

### 2.2 Enhanced Error Handling
- [ ] Visual feedback for operations (toast notifications)
- [ ] "No results" message for empty searches
- [ ] Validation messages for invalid paths
- [ ] Error recovery suggestions

**Design - Toast Notification**:
```
┌─────────────────────────────────────┐
│ ✅ Successfully saved 42 packages   │
└─────────────────────────────────────┘
```

**Estimated Effort**: 3-4 hours

---

### 2.3 Keyboard Shortcuts Legend
- [ ] Add persistent footer with common shortcuts
- [ ] Toggle detailed help with `?`
- [ ] Context-sensitive hints

**Estimated Effort**: 2-3 hours

---

### 2.4 Tooltips and Inline Help
- [ ] Hover-style help for complex features
- [ ] Contextual hints in status bar
- [ ] First-run tutorial overlay

**Estimated Effort**: 4-5 hours

---

## Priority 3 - Long-term Improvements

### 3.1 Async Operations
**Goal**: Make UI responsive during heavy operations

**Current Blocking Operations**:
- Artifact scanning (~1-2 seconds)
- Package loading (5,000+ entries)
- Search index building

**Implementation**:
- [ ] Convert artifact scanner to async/await
- [ ] Add background task queue
- [ ] Implement cancellation support
- [ ] Show progress for long-running tasks

**Estimated Effort**: 8-10 hours

---

### 3.2 Search History
- [ ] Remember recent searches
- [ ] Navigate history with ↑↓ in search mode
- [ ] Persist search history to config

**Estimated Effort**: 3-4 hours

---

### 3.3 Export/Import Selections
- [ ] Export to JSON
- [ ] Export to CSV
- [ ] Import from JSON
- [ ] Merge imported selections

**Estimated Effort**: 4-5 hours

---

### 3.4 Performance Optimizations

#### 3.4.1 Lazy Package Loading
**Current**: Loads all 9,699 packages at startup
**Proposed**: Load on-demand as user scrolls

**Benefits**:
- Faster startup (< 100ms vs ~500ms)
- Lower memory usage
- Better scalability

**Implementation**:
- [ ] Implement virtual scrolling
- [ ] Load packages in chunks (100 at a time)
- [ ] Cache loaded chunks
- [ ] Prefetch next chunk

**Estimated Effort**: 6-8 hours

---

#### 3.4.2 Differential Rendering
**Current**: Full screen redraw every frame
**Proposed**: Only redraw changed regions

**Benefits**:
- Reduced CPU usage
- Less flicker
- Better terminal compatibility

**Implementation**:
- [ ] Track dirty regions
- [ ] Implement screen diffing
- [ ] Optimize ANSI output

**Estimated Effort**: 8-10 hours

---

#### 3.4.3 Artifact Scan Caching
**Current**: Rescans library on every view
**Proposed**: Cache scan results, invalidate on FS change

**Benefits**:
- Instant library view loads
- Reduced I/O
- Better UX

**Implementation**:
- [ ] Add cache layer for artifact metadata
- [ ] Implement FS change detection
- [ ] Add cache invalidation
- [ ] Persist cache across sessions

**Estimated Effort**: 5-6 hours

---

### 3.5 Advanced Architecture

#### 3.5.1 Protocol-Based View System
```swift
protocol View {
    func render(context: RenderContext) -> String
    func handleInput(_ key: Key) -> InputResult
    func willAppear()
    func willDisappear()
}
```

**Benefits**:
- Testable views in isolation
- Reusable view components
- Cleaner separation of concerns

**Estimated Effort**: 10-12 hours

---

#### 3.5.2 Event-Driven Architecture
```swift
enum AppEvent {
    case packageSelected(PackageEntry)
    case packageToggled(PackageEntry)
    case filterChanged(FilterMode)
    case searchQueryUpdated(String)
    case viewChanged(ViewMode)
    case saveRequested
}

protocol EventHandler {
    func handle(_ event: AppEvent) async
}
```

**Benefits**:
- Decoupled components
- Easier testing
- Better debugging
- Event logging/replay

**Estimated Effort**: 12-15 hours

---

#### 3.5.3 State Machine for View Transitions
```swift
enum ViewState {
    case home
    case packages(PackagesState)
    case library(LibraryState)
    case settings(SettingsState)
    case help

    func transition(via: ViewTransition) -> ViewState?
}
```

**Benefits**:
- Predictable navigation
- No invalid states
- Easy to test
- Visual state diagram

**Estimated Effort**: 6-8 hours

---

## Code Quality Improvements

### Testing Enhancements

#### Current State (63 tests)
- ✅ AppState (filtering, sorting, search, cursor)
- ✅ PackageEntry (selection, download status)
- ✅ Infrastructure (Colors, Box, Screen, Input)
- ✅ ConfigManager (load, save, validate)
- ✅ Views (Home, Settings, Library, Package)

#### Needed Tests
- [ ] Mock FileManager in tests (currently uses live FS)
- [ ] Integration tests for view transitions
- [ ] Performance tests (render time <16ms for 60fps)
- [ ] Terminal edge cases:
  - [ ] Very small terminal (< 80x24)
  - [ ] Unicode rendering issues
  - [ ] Non-ASCII characters in paths
  - [ ] Emoji support

**Estimated Effort**: 8-10 hours

---

### Error Handling & Recovery

#### Terminal State Recovery
**Problem**: Terminal may be left in broken state on crash

**Solution**:
```swift
final class TerminalStateGuard {
    private var savedState: TerminalState?

    func save() { /* capture current state */ }
    func restore() { /* restore on crash */ }
}

// Usage with defer
func run() async {
    let guard = TerminalStateGuard()
    guard.save()
    defer { guard.restore() }

    // ... TUI code
}
```

**Tasks**:
- [ ] Implement state capture/restore
- [ ] Add signal handlers (SIGINT, SIGTERM)
- [ ] Test recovery after crash
- [ ] Document escape sequences used

**Estimated Effort**: 4-5 hours

---

### Performance Profiling

#### Metrics to Track
- Startup time
- Frame time (target: <16ms for 60fps)
- Input latency (target: <50ms)
- Memory usage
- Search performance

#### Tools
- Instruments (Time Profiler)
- Custom benchmarks
- Continuous monitoring

**Tasks**:
- [ ] Add performance benchmarks
- [ ] Profile rendering pipeline
- [ ] Identify bottlenecks
- [ ] Optimize hot paths

**Estimated Effort**: 6-8 hours

---

## Documentation Improvements

### Needed Documentation
- [ ] TUI architecture overview (this document is a start!)
- [ ] View system documentation
- [ ] State management patterns
- [ ] Testing strategy for TUI
- [ ] Architecture diagrams (view hierarchy, data flow)
- [ ] API reference for public interfaces
- [ ] Integration guide for new views
- [ ] Screenshots/animated demos for README

**Estimated Effort**: 8-10 hours

---

## Feature Ideas (Not Prioritized)

### Nice-to-Have Features
- [ ] Package comparison view (side-by-side)
- [ ] Trending packages (most stars this week/month)
- [ ] Package dependencies visualization
- [ ] GitHub activity timeline
- [ ] Similar packages recommendations
- [ ] Package quality scores
- [ ] Tag-based filtering
- [ ] Custom package lists (multiple priority lists)
- [ ] Sync selections across devices
- [ ] Dark/light theme toggle
- [ ] Custom color schemes
- [ ] Vim-style command mode (`:save`, `:quit`)
- [ ] Macro recording (record/replay key sequences)
- [ ] Split-pane view (browse + details)

---

## Technical Debt

### Known Issues
1. **500-line event loop** - Needs refactoring (Priority 1.3)
2. **No dependency injection** - Hard to test, tight coupling
3. **Manual construction everywhere** - Verbose, error-prone
4. **Blocking I/O operations** - UI freezes during scans
5. **No error recovery** - Terminal state may be corrupted
6. **Full screen redraws** - Wasteful, causes flicker
7. **No input validation** - Can enter invalid state
8. **Memory usage** - All packages loaded upfront

### Refactoring Opportunities
- Extract view components (header, footer, menu)
- Create reusable UI primitives (list, table, form)
- Standardize color usage (theme system)
- Unify error handling patterns
- Add logging infrastructure

---

## Success Metrics

### Performance Targets
- Startup time: < 200ms
- Frame time: < 16ms (60fps)
- Input latency: < 50ms
- Memory usage: < 50MB
- Search response: < 100ms

### Code Quality Targets
- Test coverage: > 80%
- No files > 300 lines
- No functions > 50 lines
- SwiftLint warnings: 0
- Documentation coverage: 100% public API

### User Experience Targets
- First-time users can complete task without help
- Power users have keyboard shortcuts for everything
- No operation feels slow or unresponsive
- Clear feedback for all actions
- Graceful error handling with recovery suggestions

---

## References

- [Original TODO.md](TODO.md) - Contains items 1-13
- [Comprehensive Analysis](COMPREHENSIVE_ANALYSIS_2025-11-19.md) - Full codebase analysis
- [AI Rules](../ai-rules/) - Development guidelines and patterns
- [TUI Source](../../Packages/Sources/TUI/) - Implementation
- [TUI Tests](../../Packages/Tests/TUITests/) - Test suite

---

**Last Updated**: 2025-11-19
**Status**: Living document - will be updated as features are completed
