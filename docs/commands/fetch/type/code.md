# --type code

Fetch Apple Sample Code Projects

## Synopsis

```bash
cupertino fetch --type code --authenticate
```

## Description

Downloads Apple's official sample code projects as ZIP files. These are complete, compilable Xcode projects demonstrating various frameworks and APIs.

## Requirements

- `--authenticate` flag (required)
- Valid Apple ID
- macOS with Safari
- Internet connection

## Output

Creates individual ZIP files:
- One ZIP per sample code project
- Original filenames preserved
- Checkpoint.json tracks progress

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/sample-code` |
| Authentication | **Required** (`--authenticate`) |
| Estimated Count | ~600 sample projects |

## Examples

### Fetch All Sample Code
```bash
cupertino fetch --type code --authenticate
```

### Fetch Limited Number
```bash
cupertino fetch --type code --authenticate --limit 50
```

### Custom Output Directory
```bash
cupertino fetch --type code --authenticate --output-dir ./samples
```

### Resume Interrupted Download
```bash
cupertino fetch --type code --authenticate --resume
```

## Authentication Process

1. Command opens Safari browser
2. Navigate to Apple Developer sample code
3. Sign in with your Apple ID
4. Download begins automatically
5. Browser closes when complete

## Output Structure

```
~/.cupertino/sample-code/
├── checkpoint.json
├── swiftui-building-lists-and-navigation.zip
├── arkit-creating-a-collaborative-session.zip
├── uikit-implementing-modern-collection-views.zip
└── ... (600+ files)
```

## Sample Code Categories

- **SwiftUI** - Modern UI framework examples
- **UIKit** - Traditional UI examples
- **ARKit** - Augmented reality
- **Core ML** - Machine learning
- **Combine** - Reactive programming
- **And many more** - All Apple frameworks

## Use Cases

- Learning Apple APIs
- Reference implementations
- Starting templates
- Best practices examples
- Framework exploration

## Notes

- **Authentication is required** - Cannot download without Apple ID
- Free Apple Developer account works
- Downloads complete Xcode projects
- ZIP files can be unarchived and opened in Xcode
- Projects are ready to build and run
- Covers iOS, macOS, watchOS, tvOS, visionOS
