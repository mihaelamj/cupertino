# Development Guide

Complete guide for local development, building, testing, and contributing to Cupertino.

> **Important:** All `make` commands work from both the **root directory** and the **Packages directory**. The root Makefile automatically delegates to Packages/Makefile. Swift Package Manager commands (`swift build`, `swift test`) must be run from the Packages directory.

## Table of Contents

1. [Requirements](#requirements)
2. [Local Build Setup](#local-build-setup)
3. [Project Structure](#project-structure)
4. [Development Workflow](#development-workflow)
5. [Testing](#testing)
6. [Code Style](#code-style)
7. [Debugging](#debugging)
8. [Common Tasks](#common-tasks)

---

## Requirements

### System Requirements

- **macOS:** 15.0+ (Sequoia) - Required for WKWebView APIs
- **Xcode:** 16.0+
- **Swift:** 6.2+
- **Disk Space:** ~500MB for build artifacts, 2-3GB for full documentation

### Development Tools (Optional)

- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) - Code formatting
- [SwiftLint](https://github.com/realm/SwiftLint) - Linting
- [pre-commit](https://pre-commit.com) - Git hooks

---

## Local Build Setup

### 1. Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/cupertino.git
cd cupertino
```

### 2. Build All Targets

**Using Makefile (Recommended):**

The Makefile works from **either** the root directory or the Packages directory:

```bash
# From root directory
cd cupertino
make build

# OR from Packages directory
cd cupertino/Packages
make build

# Shortcuts work from both locations
make b              # Same as 'make build'
make build-debug    # Debug build
make build-release  # Release build
```

**Using Swift Package Manager directly:**

```bash
cd Packages  # Must be in Packages directory
swift build
```

**Build time:** ~10-30s (first build), ~2-5s (incremental)

**Output location:**
- Debug binaries: `Packages/.build/debug/`
- Release binaries: `Packages/.build/release/`

### 3. Build for Release (Optimized)

**Using Makefile (works from root or Packages):**

```bash
make build-release
```

**Using Swift Package Manager (must be in Packages directory):**

```bash
cd Packages
swift build -c release
```

**Binary locations:**
- `Packages/.build/release/cupertino` (~4.3MB)
- `Packages/.build/release/cupertino-mcp` (~4.4MB)

### 4. Install Globally

#### Option 1: Install (Recommended)

Copies binaries to /usr/local/bin.

**Using Makefile (Easiest - works from root or Packages):**

```bash
# From root directory
cd cupertino
make build                       # Build binaries
sudo make install                # Install to /usr/local/bin

# OR from Packages directory
cd cupertino/Packages
make build                       # Build binaries
sudo make install                # Install to /usr/local/bin

# Verify
which cupertino
cupertino --version
```

**To update after code changes (works from root or Packages):**

```bash
sudo make update  # Rebuilds and reinstalls
```

**Manual installation:**

```bash
cd Packages
swift build -c release

# Create symlinks
sudo ln -sf "$(pwd)/.build/release/cupertino" /usr/local/bin/cupertino
sudo ln -sf "$(pwd)/.build/release/cupertino-mcp" /usr/local/bin/cupertino-mcp

# Verify
which cupertino
cupertino --version
```

#### Option 2: Symlinks (Advanced)

Changes reflected immediately after rebuild - no reinstall needed. Can have PATH issues with sudo.

**Using Makefile (works from root or Packages):**

```bash
make build
sudo make install-symlinks
```

**To update:**

```bash
make update  # Just rebuild, symlinks auto-update
```

#### Option 3: Use Directly from Build Directory

No installation needed.

```bash
cd Packages
swift build

# Use with full path
./build/debug/cupertino --help
./build/debug/cupertino-mcp --help
```

### Quick Update Workflow

**Recommended: Use Makefile (works from root or Packages directory)**

```bash
# One-time setup (from either root or Packages directory)
make build                       # Build binaries
sudo make install                # Install to /usr/local/bin

# Development iteration
# 1. Make code changes
# 2. Run (from either root or Packages directory):
sudo make update                 # Rebuild and reinstall

# That's it! Changes are installed and ready.
```

**Alternative: Manual Script**

Save this as `update.sh` in the root directory:

```bash
#!/bin/bash
# Quick development update script

set -e  # Exit on error

echo "🔨 Building release..."
cd Packages
swift build -c release

echo "✅ Build complete!"
echo ""
echo "If using symlinks, changes are already live."
echo "If using copies, run:"
echo "  sudo cp .build/release/cupertino /usr/local/bin/"
echo "  sudo cp .build/release/cupertino-mcp /usr/local/bin/"
```

Make it executable:

```bash
chmod +x update.sh
./update.sh
```

---

## Project Structure

Cupertino uses an **[ExtremePackaging](https://aleahim.com/blog/extreme-packaging/)** architecture with 9 separate packages organized in layers:

```
Packages/
├── Package.swift                    # Main package manifest
│
├── Sources/
│   ├── Foundation Layer (No dependencies)
│   │   ├── MCPShared/              # MCP protocol models
│   │   ├── CupertinoLogging/       # os.log infrastructure
│   │   └── CupertinoShared/        # Configuration & models
│   │
│   ├── Infrastructure Layer
│   │   ├── MCPTransport/           # JSON-RPC transport (stdio)
│   │   ├── MCPServer/              # MCP server implementation
│   │   └── CupertinoCore/          # Crawler & downloaders
│   │
│   ├── Application Layer
│   │   ├── CupertinoSearch/        # SQLite FTS5 search
│   │   ├── CupertinoMCPSupport/    # Resource providers
│   │   └── CupertinoSearchToolProvider/ # Search tools
│   │
│   └── Executables
│       ├── CupertinoCLI/           # CLI tool (main.swift)
│       └── CupertinoMCP/           # MCP server (main.swift)
│
└── Tests/
    ├── MCPSharedTests/
    ├── MCPServerTests/
    ├── CupertinoCoreTests/
    ├── CupertinoSearchTests/
    ├── CupertinoLoggingTests/
    └── ... (one test target per package)
```

### Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | Swift Package Manager manifest |
| `Sources/CupertinoCLI/main.swift` | CLI entry point |
| `Sources/CupertinoMCP/main.swift` | MCP server entry point |
| `Sources/CupertinoCore/Crawler.swift` | Main documentation crawler |
| `Sources/CupertinoSearch/SearchIndex.swift` | SQLite FTS5 search engine |

---

## Development Workflow

### 1. Make Code Changes

Edit files in `Packages/Sources/`:

```bash
# Example: Edit the crawler
vim Packages/Sources/CupertinoCore/Crawler.swift
```

### 2. Build

**Using Makefile (works from root or Packages):**
```bash
make build
```

**Using Swift Package Manager (must be in Packages directory):**
```bash
cd Packages
swift build
```

### 3. Test

**Using Makefile (works from root or Packages):**
```bash
make test
```

**Using Swift Package Manager (must be in Packages directory):**
```bash
cd Packages
swift test
```

### 4. Run Locally

```bash
# From Packages directory
cd Packages
.build/debug/cupertino --help
.build/debug/cupertino-mcp serve

# OR if installed globally
cupertino --help
cupertino-mcp serve
```

### 5. Update Global Installation

**Using Makefile (works from root or Packages):**
```bash
make update  # Rebuilds and symlinks automatically use new build!
```

**Manual (must be in Packages directory):**
```bash
cd Packages
swift build -c release
# Symlinks automatically point to new build!
```

### Typical Development Iteration

**Using Makefile (Recommended):**
```bash
# 1. Edit code
vim Packages/Sources/CupertinoCore/Crawler.swift

# 2. Build and test (from root or Packages directory)
make build && make test

# 3. Test locally (if installed globally)
cupertino fetch --max-pages 1 --output-dir /tmp/test

# 4. If looks good, update (from root or Packages directory)
make update

# 5. Done! Changes are live.
```

**Using Swift Package Manager directly:**
```bash
# 1. Edit code
vim Packages/Sources/CupertinoCore/Crawler.swift

# 2. Build and test (must be in Packages directory)
cd Packages
swift build && swift test

# 3. Test locally
.build/debug/cupertino fetch --max-pages 1 --output-dir /tmp/test

# 4. If looks good, rebuild release
swift build -c release

# 5. Symlinks automatically use new build - done!
```

---

## Testing

### Run All Tests

```bash
cd Packages
swift test
```

**Expected output:**
```
✅ 11/11 tests passed (0 failures)
```

### Run Specific Tests

```bash
# Run specific test file
swift test --filter CupertinoCoreTests

# Run specific test
swift test --filter testDownloadRealAppleDocPage
```

### Integration Tests

The project includes an integration test that downloads a real Apple doc page:

```bash
swift test --filter testDownloadRealAppleDocPage
```

**Output:**
```
🧪 Integration Test: Downloading real Apple doc page...
   URL: https://developer.apple.com/documentation/swift
   ✅ Crawled 1 page(s)
   ✅ Content size: 7157 characters
🎉 Integration test passed!
```

### Test Coverage

Run tests with coverage (requires Xcode):

```bash
swift test --enable-code-coverage
```

View coverage report in Xcode:
1. Open `Package.swift` in Xcode
2. Run tests (⌘U)
3. View coverage: Editor → Show Code Coverage

### Manual Testing

Test the full workflow locally:

```bash
# 1. Download small sample
.build/debug/cupertino fetch \
  --start-url "https://developer.apple.com/documentation/swift/array" \
  --max-pages 3 \
  --output-dir /tmp/docsucker-test

# 2. Verify output
find /tmp/docsucker-test -name "*.md"

# 3. Build search index
.build/debug/cupertino build-index \
  --docs-dir /tmp/docsucker-test \
  --search-db /tmp/docsucker-test/search.db

# 4. Start MCP server
.build/debug/cupertino-mcp serve \
  --docs-dir /tmp/docsucker-test \
  --search-db /tmp/docsucker-test/search.db
```

---

## Code Style

### SwiftFormat

Install:

```bash
brew install swiftformat
```

Format code:

```bash
cd Packages
swiftformat . --config .swiftformat
```

Configuration: `.swiftformat` (if exists) or default rules:
- 4-space indentation
- ≤180 character line width
- Trailing commas

### SwiftLint

Install:

```bash
brew install swiftlint
```

Lint code:

```bash
cd Packages
swiftlint --config .swiftlint.yml
```

### Pre-commit Hooks

Install pre-commit:

```bash
brew install pre-commit
cd /path/to/cupertino
pre-commit install
```

Run manually:

```bash
pre-commit run --all-files
```

### Style Guidelines

- **Indentation:** 4 spaces
- **Line width:** ≤180 characters
- **Trailing commas:** Always
- **Dependencies:** Inject via Point-Free Dependencies pattern
- **Error handling:** Use Result types or throw specific errors
- **Concurrency:** Use actors for shared mutable state
- **Logging:** Use DocsuckerLogger.* for all logging

---

## Debugging

### Debug Builds

Debug builds include symbols and are slower but easier to debug:

```bash
swift build  # Defaults to debug
lldb .build/debug/cupertino
```

### Console Logging

View os.log output:

```bash
# Stream live logs
log stream --predicate 'subsystem == "com.docsucker.cupertino"'

# View recent logs
log show --predicate 'subsystem == "com.docsucker.cupertino"' --last 1h

# Filter by category
log show --predicate 'subsystem == "com.docsucker.cupertino" AND category == "crawler"' --last 1h
```

### Xcode Debugging

1. Open `Package.swift` in Xcode
2. Select scheme: `cupertino` or `cupertino-mcp`
3. Edit scheme → Run → Arguments → Add command-line args
4. Set breakpoints
5. Run (⌘R)

### Common Debug Commands

```bash
# Verbose output (if implemented)
cupertino fetch --verbose

# Test with small sample
cupertino fetch --max-pages 1 --output-dir /tmp/test

# Check file permissions
ls -la ~/.cupertino/

# Verify SQLite database
sqlite3 ~/.cupertino/search.db "SELECT COUNT(*) FROM docs_fts;"
```

---

## Common Tasks

### Add New Command to CLI

1. Edit `Sources/CupertinoCLI/main.swift`
2. Create new `struct` conforming to `AsyncParsableCommand`
3. Add to subcommands in `CommandConfiguration`
4. Implement `run()` method

Example:

```swift
extension Cupertino {
    struct MyNewCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Description of my command"
        )

        func run() async throws {
            ConsoleLogger.info("Running my new command!")
            // Implementation here
        }
    }
}

// Add to main configuration:
static let configuration = CommandConfiguration(
    commandName: "cupertino",
    subcommands: [..., MyNewCommand.self]
)
```

### Add New MCP Resource Type

1. Edit `Sources/CupertinoMCPSupport/CupertinoResourceProvider.swift`
2. Add new URI scheme handling in `readResource()`
3. Update `listResources()` to include new resources

### Add New Search Feature

1. Edit `Sources/CupertinoSearch/SearchIndex.swift`
2. Add new SQL queries or FTS5 features
3. Update `Sources/CupertinoSearchToolProvider/CupertinoSearchToolProvider.swift` to expose via MCP

### Update Dependencies

```bash
cd Packages
swift package update
swift build
swift test
```

### Clean Build

```bash
cd Packages
swift package clean
swift build
```

### Generate Documentation

```bash
cd Packages
swift package generate-documentation
```

---

## Performance Profiling

### Measure Build Time

```bash
time swift build -c release
```

### Measure Crawl Performance

```bash
time .build/release/cupertino fetch --max-pages 100 --output-dir /tmp/perf-test
```

### Profile with Instruments

1. Build with profiling enabled
2. Run Instruments (Xcode → Open Developer Tool → Instruments)
3. Select "Time Profiler" or "Allocations"
4. Attach to running process

---

## Troubleshooting

### Build Errors

**Error:** `Cannot find 'X' in scope`

**Solution:** Add import statement or dependency in Package.swift

**Error:** `Could not resolve package dependencies`

**Solution:**

```bash
swift package resolve
swift package update
```

### Test Failures

**Error:** Integration test fails to download

**Solution:** Check internet connection and Apple's documentation site status

### Runtime Errors

**Error:** `Search index not found`

**Solution:** Run `cupertino build-index` first

**Error:** `Permission denied`

**Solution:** Check file permissions on output directory

---

## Release Checklist

Before creating a new release:

- [ ] Update version in `Package.swift` and `main.swift` files
- [ ] Run all tests: `swift test`
- [ ] Check code formatting: `swiftformat --lint .`
- [ ] Run SwiftLint: `swiftlint`
- [ ] Build release: `swift build -c release`
- [ ] Test executables manually
- [ ] Update README.md with new features
- [ ] Update CHANGELOG.md (if exists)
- [ ] Create git tag: `git tag -a v1.x.x -m "Release 1.x.x"`
- [ ] Push tag: `git push origin v1.x.x`

---

## Resources

- **Swift Package Manager:** https://swift.org/package-manager/
- **Swift Argument Parser:** https://github.com/apple/swift-argument-parser
- **Model Context Protocol:** https://modelcontextprotocol.io
- **SQLite FTS5:** https://www.sqlite.org/fts5.html
- **os.log:** https://developer.apple.com/documentation/os/logging

---

## Getting Help

- **Issues:** [GitHub Issues](https://github.com/YOUR_USERNAME/cupertino/issues)
- **Discussions:** [GitHub Discussions](https://github.com/YOUR_USERNAME/cupertino/discussions)
- **Documentation:** See README.md and Packages/*.md files

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run `swift test` and `swiftformat`
6. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines (if exists).
