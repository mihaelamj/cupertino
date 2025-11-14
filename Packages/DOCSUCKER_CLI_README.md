# Docsucker CLI - Apple Documentation Crawler

A Swift command-line tool for downloading and converting Apple documentation to Markdown format.

## Features

- 🚀 **Fast WKWebView-based crawling** - Uses native WebKit for accurate rendering
- 📝 **HTML to Markdown conversion** - Clean, readable documentation in Markdown format with code syntax highlighting
- 🔍 **Smart change detection** - SHA-256 content hashing to skip unchanged pages
- 📊 **Progress tracking** - Real-time statistics and progress updates
- 🎯 **Framework organization** - Automatically organizes docs by framework
- 🔄 **Incremental updates** - Only re-downloads changed content
- 🐙 **Swift Evolution proposals** - Download all accepted Swift Evolution proposals from GitHub
- 📦 **Sample code downloads** - Download Apple sample code projects as zip/tar files
- 📄 **PDF export** - Convert markdown documentation to beautifully formatted PDF files

## Installation

### Build from source:

```bash
cd Packages
swift build --product docsucker
```

The executable will be at: `.build/debug/appledocsucker`

### Install to /usr/local/bin (optional):

```bash
swift build -c release --product docsucker
cp .build/release/docsucker /usr/local/bin/
```

## Usage

### 1. Download All Apple Documentation

To download the complete Apple documentation library:

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --max-depth 15 \
  --output-dir ~/.docsucker/docs
```

**Parameters:**
- `--start-url` - Starting URL to crawl from
- `--max-pages` - Maximum number of pages to download (default: 15000)
- `--max-depth` - Maximum link depth to follow (default: 15)
- `--output-dir` - Where to save the documentation (default: `~/.docsucker/docs`)
- `--force` - Force recrawl all pages (ignore cache)

**Estimated time:** 2-4 hours for full documentation
**Estimated size:** ~2-3 GB

### 2. Download Specific Framework Documentation

Download just SwiftUI documentation:

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/swiftui" \
  --max-pages 500 \
  --output-dir ~/docs/swiftui
```

Download just Foundation framework:

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/foundation" \
  --max-pages 1000 \
  --output-dir ~/docs/foundation
```

### 3. Download All Swift Evolution Proposals

Download all accepted Swift Evolution proposals from GitHub:

```bash
appledocsucker crawl-evolution \
  --output-dir ~/.docsucker/swift-evolution
```

This will:
- Fetch the list of all proposals from swift-evolution GitHub repo
- Download each `.md` file from the proposals directory
- Save them with original filenames (e.g., `SE-0001-keywords-as-argument-labels.md`)
- Track which proposals are new/updated

**Estimated time:** 2-5 minutes
**Estimated size:** ~10-20 MB

### 4. Download Apple Sample Code Projects

Download Apple sample code projects as zip/tar files:

**First time - Authenticate with Apple:**

```bash
appledocsucker download-samples \
  --authenticate \
  --output-dir ~/.docsucker/sample-code \
  --max-samples 10
```

This will:
1. Open a browser window showing the Apple Developer sign-in page
2. Wait for you to sign in with your Apple ID
3. Save your authentication cookies
4. Proceed to download samples

**Subsequent downloads (reuses saved authentication):**

```bash
appledocsucker download-samples \
  --output-dir ~/.docsucker/sample-code \
  --max-samples 100
```

**Parameters:**
- `--authenticate` - Launch visible browser for authentication (use on first run)
- `--output-dir` - Where to save sample code files (default: `~/.docsucker/sample-code`)
- `--max-samples` - Limit number of samples to download (optional, downloads all if not specified)
- `--force` - Force re-download of existing files

This will:
- Scan the Apple Sample Code Library (~618 samples)
- Extract download links from each sample page
- Download the original zip/tar files with clean filenames
- Skip already downloaded files (unless `--force` is used)

**Example output:**
```
🚀 Sample Code Downloader

📋 Fetching sample code list...
   Found 618 samples
   Downloading 100 samples

📦 [1/100] Landmarks: Building an app with Liquid Glass
   📥 Downloading from: https://developer.apple.com/...
   ✅ Saved: landmarks-building-an-app-with-liquid-glass.zip
   Progress: 1.0%

...

✅ Download completed!
   Total: 100 samples
   Downloaded: 95
   Skipped: 5
   Errors: 0
   Duration: 180s
```

**Important Notes:**
- 🔐 **Authentication**: Use `--authenticate` on first run to sign in with your Apple Developer account. Cookies are saved to `.auth-cookies.json` in the output directory
- 📦 Some samples may be distributed as `.zip`, others as `.tar.gz` - the tool handles both automatically
- 🔍 The tool first catalogs all available samples (~618 total), then downloads each one
- ⏱️ Rate limiting is applied (1 second delay between downloads) to be respectful to Apple's servers
- 🔄 **Reusing authentication**: After first successful authentication, cookies are reused automatically for subsequent downloads
- 🗑️ **Clear auth**: Delete `.auth-cookies.json` to sign in with a different account

**Estimated time:** Variable (depends on number of samples and authentication)
**Estimated size:** Varies per sample (typically 50KB - 50MB each)

### 5. Export Documentation to PDF

Convert downloaded markdown documentation to PDF format:

```bash
appledocsucker export-pdf \
  --input-dir ~/.docsucker/docs \
  --output-dir ~/.docsucker/pdfs
```

**Parameters:**
- `--input-dir` - Directory containing markdown files (default: `~/.docsucker/docs`)
- `--output-dir` - Directory for PDF output (default: `~/.docsucker/pdfs`)
- `--max-files` - Limit number of files to convert (optional)
- `--force` - Force re-export of existing PDFs

This will:
- Scan the input directory recursively for `.md` files
- Convert each markdown file to a styled PDF
- Preserve the directory structure in the output
- Skip already exported files (unless `--force` is used)

**Example output:**
```
📄 PDF Exporter

📋 Scanning for markdown files...
   Found 150 markdown files
   Exporting 150 files

📄 [1/150] documentation_swift_array.md
   ✅ Exported: documentation_swift_array.pdf
   Progress: 0.7%

...

✅ Export completed!
   Total: 150 files
   Exported: 145
   Skipped: 5
   Errors: 0
   Duration: 120s
```

**PDF Features:**
- 📝 **Styled formatting** - Clean, readable layout with proper typography
- 💻 **Syntax highlighting** - Code blocks with language-specific formatting
- 📄 **A4 page size** - Standard 595x842 points
- 🎨 **Custom CSS** - Matches GitHub markdown styling
- 📚 **Preserves structure** - Headers, links, lists, bold, italic, code

**Estimated time:** ~1 second per file
**Estimated size:** Typically 50-500KB per PDF

### 6. Update Existing Documentation (Incremental)

Re-run crawl to update only changed pages:

```bash
appledocsucker update \
  --output-dir ~/.docsucker/docs
```

This uses the saved metadata to:
- Skip unchanged pages (based on SHA-256 hash)
- Only download new or modified content
- Much faster than full crawl

### 5. Configuration Management

Initialize default configuration:

```bash
appledocsucker config init
```

View current configuration:

```bash
appledocsucker config show
```

Configuration is saved to: `~/.docsucker/config.json`

## Output Format

### Directory Structure

```
~/.docsucker/docs/
├── swift/
│   ├── documentation_swift_array.md
│   ├── documentation_swift_string.md
│   └── documentation_swift_int.md
├── swiftui/
│   ├── documentation_swiftui_view.md
│   ├── documentation_swiftui_text.md
│   └── ...
├── foundation/
│   ├── documentation_foundation_url.md
│   └── ...
└── .docsucker/
    └── metadata.json
```

### Markdown Format

Each page includes YAML front matter:

```markdown
---
source: https://developer.apple.com/documentation/swift/array
crawled: 2025-11-14T10:30:00Z
---

# Array

An ordered, random-access collection.

## Overview

Arrays are one of the most commonly used data types...
```

## Examples

### Download Top 100 Swift Pages

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/swift" \
  --max-pages 100 \
  --max-depth 3 \
  --output-dir ~/swift-docs-sample
```

### Force Re-download Everything

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/" \
  --max-pages 15000 \
  --force \
  --output-dir ~/.docsucker/docs
```

### Download with Custom Settings

```bash
appledocsucker crawl \
  --start-url "https://developer.apple.com/documentation/combine" \
  --max-pages 200 \
  --max-depth 5 \
  --output-dir ~/combine-docs
```

## Statistics & Progress

During crawling, you'll see real-time progress:

```
🚀 Docsucker - Apple Documentation Crawler

🚀 Starting crawl
   Start URL: https://developer.apple.com/documentation/swift
   Max pages: 100
   Output: ~/.docsucker/docs

📄 [1/100] depth=0 [swift] https://developer.apple.com/documentation/swift
   ✅ Saved new page: documentation_swift.md
   Progress: 1.0% - swift

📄 [2/100] depth=1 [swift] https://developer.apple.com/documentation/swift/array
   ✅ Saved new page: documentation_swift_array.md
   Progress: 2.0% - array

...

✅ Crawl completed!
📊 Statistics:
   Total pages processed: 100
   New pages: 85
   Updated pages: 10
   Skipped (unchanged): 5
   Errors: 0
   Duration: 180s

📁 Output: ~/.docsucker/docs
```

## Configuration File Format

`~/.docsucker/config.json`:

```json
{
  "crawler": {
    "startURL": "https://developer.apple.com/documentation/",
    "maxPages": 15000,
    "maxDepth": 15,
    "outputDirectory": "~/.docsucker/docs",
    "requestDelay": 0.5
  },
  "changeDetection": {
    "enabled": true,
    "forceRecrawl": false
  },
  "output": {
    "format": "markdown"
  }
}
```

## Troubleshooting

### Error: Permission Denied

Make sure the output directory is writable:

```bash
mkdir -p ~/.docsucker/docs
chmod 755 ~/.docsucker/docs
```

### Error: Network Timeout

Increase timeout in the crawler configuration or check your internet connection.

### Pages Showing "JavaScript Required"

Some pages require JavaScript. The WKWebView crawler handles this automatically by rendering pages before extracting content.

### Too Many Errors

Some documentation pages may be inaccessible or moved. The crawler will continue and report errors at the end.

## Best Practices

1. **Start Small**: Test with `--max-pages 10` first
2. **Use Incremental Updates**: Run `appledocsucker update` regularly instead of full re-crawls
3. **Monitor Disk Space**: Full docs can be 2-3 GB
4. **Be Respectful**: Default 0.5s delay between requests is reasonable
5. **Backup Metadata**: Keep `.docsucker/metadata.json` for change detection

## Use Cases

- **Offline Documentation**: Access Apple docs without internet
- **Full-Text Search**: Use grep/ripgrep across all docs
- **AI Training**: Feed documentation to AI models
- **Custom Documentation Sites**: Build your own doc viewer
- **Version Tracking**: Track documentation changes over time

## See Also

- [MCP Server README](./MCP_SERVER_README.md) - Serve docs to AI agents
- [Swift Evolution](https://github.com/swiftlang/swift-evolution) - Proposal source
