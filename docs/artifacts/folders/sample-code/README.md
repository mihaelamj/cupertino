# sample-code/ - Apple Sample Code Projects

Downloaded Apple sample code projects - either as ZIP files or extracted folders.

## Location

**Default**: `~/.cupertino/sample-code/`

## Created By

```bash
# Option 1: GitHub (recommended - faster, no auth required)
cupertino fetch --type samples

# Option 2: Apple Website (slower, requires Apple ID)
cupertino fetch --type code --authenticate
```

## Structure

```
~/.cupertino/sample-code/
├── checkpoint.json                                          # Progress tracking (code type)
├── cupertino-sample-code/                                   # GitHub clone (samples type)
│   ├── .git/
│   ├── accelerate-adding-a-bokeh-effect-to-images/
│   ├── arkit-creating-a-collaborative-session/
│   ├── swiftui-building-lists-and-navigation/
│   └── ...                                                  # 606 extracted projects
├── accelerate-adding-a-bokeh-effect-to-images.zip           # ZIP files (code type)
├── arkit-creating-a-collaborative-session.zip
└── ...                                                      # 600+ ZIP files
```

## Contents

### GitHub Clone (samples type)
- **606 sample code projects** as extracted folders
- Cloned from https://github.com/mihaelamj/cupertino-sample-code
- Uses Git LFS for large binary files (~10GB total)
- Ready to open in Xcode immediately
- Pull to update: `cd cupertino-sample-code && git pull`

### ZIP Files (code type)
- **~600 sample code projects** as ZIP archives
- Downloaded directly from Apple Developer website
- Complete Xcode projects
- Ready to build and run
- Covers all Apple platforms (iOS, macOS, watchOS, tvOS, visionOS)

### File Naming Convention
Format: `framework-description-of-sample.zip`

Examples:
- `accelerate-adding-a-bokeh-effect-to-images.zip`
- `accelerate-blurring-an-image.zip`
- `accelerate-calculating-the-dominant-colors-in-an-image.zip`
- `arkit-creating-a-collaborative-session.zip`
- `swiftui-building-lists-and-navigation.zip`
- `uikit-implementing-modern-collection-views.zip`

### [checkpoint.json](../packages/checkpoint.json.md)
- Tracks download progress
- List of downloaded files
- Can resume interrupted downloads

## Sample Code Categories

| Framework | Example Projects |
|-----------|-----------------|
| SwiftUI | Modern UI, Lists, Navigation, Charts |
| UIKit | Collection Views, Table Views, Custom UI |
| ARKit | Augmented Reality, 3D experiences |
| Core ML | Machine Learning, Vision |
| Combine | Reactive programming |
| And 40+ more | Covers entire Apple ecosystem |

## Size

- **~600 ZIP files**
- **~2-5 GB total** (varies by platform support)
- Each ZIP: 100 KB - 50 MB

## Usage

### Unzip and Use in Xcode
```bash
# Unzip a sample
cd ~/.cupertino/sample-code
unzip accelerate-blurring-an-image.zip

# Open in Xcode
open accelerate-blurring-an-image/
```

### Search for Specific Framework
```bash
# Find all Accelerate samples
ls ~/.cupertino/sample-code/accelerate-*.zip

# Find all SwiftUI samples
ls ~/.cupertino/sample-code/swiftui-*.zip

# Find all ARKit samples
ls ~/.cupertino/sample-code/arkit-*.zip
```

## Authentication

### GitHub (samples type) - No authentication required
```bash
cupertino fetch --type samples
```
Requires Git and Git LFS installed:
```bash
brew install git-lfs
git lfs install
```

### Apple Website (code type) - Apple ID required
```bash
cupertino fetch --type code --authenticate
```
Must use `--authenticate` flag. Requires:
- Valid Apple ID
- Safari browser for authentication
- macOS system

## Indexing for Search

After fetching, index the samples for full-text search:
```bash
cupertino index
# or force reindex:
cupertino index --force
```

This creates `samples.db` with 18,000+ indexed source files.

## MCP Tools

After indexing, these MCP tools become available:
- `search_samples` - Search projects and code
- `list_samples` - List all indexed projects
- `read_sample` - Read project README
- `read_sample_file` - Read specific source file

## Customizing Location

```bash
# GitHub clone to custom directory
cupertino fetch --type samples --output-dir ./samples

# Apple download to custom directory
cupertino fetch --type code --authenticate --output-dir ./samples
```

## Notes

- All projects are production-ready examples
- Demonstrate Apple's best practices
- Projects are maintained and updated by Apple
- Great learning resource for all skill levels
- Can build and run immediately in Xcode
- GitHub method is recommended (faster, no auth required)
