# sample-code/ - Apple Sample Code ZIP Files

Downloaded Apple sample code projects as ZIP files.

## Location

**Default**: `~/.cupertino/sample-code/`

## Created By

```bash
cupertino fetch --type code --authenticate
```

## Structure

```
~/.cupertino/sample-code/
├── checkpoint.json                                          # Progress tracking
├── accelerate-adding-a-bokeh-effect-to-images.zip
├── arkit-creating-a-collaborative-session.zip
├── swiftui-building-lists-and-navigation.zip
├── uikit-implementing-modern-collection-views.zip
└── ...                                                      # 600+ ZIP files
```

## Contents

### ZIP Files
- **~600 sample code projects**
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

**Required**: Must use `--authenticate` flag to download sample code

Downloading requires:
- Valid Apple ID
- Safari browser for authentication
- macOS system

## Resuming Downloads

```bash
# Resume if interrupted
cupertino fetch --type code --authenticate --resume
```

## Customizing Location

```bash
# Use custom directory
cupertino fetch --type code --authenticate --output-dir ./samples
```

## Notes

- All projects are production-ready examples
- Demonstrate Apple's best practices
- Projects are maintained and updated by Apple
- Great learning resource for all skill levels
- Can build and run immediately in Xcode
