# hig

Human Interface Guidelines source

## Synopsis

```bash
cupertino search <query> --source hig
```

## Description

Filters search results to only include Apple Human Interface Guidelines. These are Apple's official design guidelines for building apps across all Apple platforms.

## Content

- **Design foundations** (color, typography, icons, layout)
- **UI patterns** (navigation, onboarding, modality)
- **Components** (buttons, pickers, text fields, etc.)
- **Technologies** (Siri, HealthKit, CarPlay, etc.)
- **Input methods** (touch, Apple Pencil, keyboard)
- **Platform-specific** guidelines for iOS, macOS, watchOS, visionOS, tvOS

## Typical Size

- **~200+ pages** indexed
- **~20-50 MB** on disk
- Updated as Apple releases new guidelines

## Examples

### Search for Component Guidelines
```bash
cupertino search "buttons" --source hig
```

### Search for Design Patterns
```bash
cupertino search "navigation" --source hig
```

### Search for Platform Guidelines
```bash
cupertino search "visionOS spatial" --source hig
```

### Search for Accessibility
```bash
cupertino search "VoiceOver accessibility" --source hig
```

## URI Format

Results use the `hig://` URI scheme:

```
hig://{category}/{page}
```

Examples:
- `hig://components/buttons`
- `hig://patterns/navigation`
- `hig://foundations/color`
- `hig://technologies/siri`

## How to Populate

```bash
# Fetch all HIG content (10-30 minutes)
cupertino fetch --type hig

# Build index
cupertino save
```

## Categories

| Category | Content |
|----------|---------|
| Foundations | Color, typography, icons, layout, motion |
| Patterns | Navigation, onboarding, modality, searching |
| Components | Buttons, pickers, text fields, sliders |
| Technologies | Siri, HealthKit, CarPlay, Apple Pay |
| Inputs | Touch, Apple Pencil, keyboard, game controllers |

## Platforms Covered

| Platform | Description |
|----------|-------------|
| iOS | iPhone and iPad guidelines |
| macOS | Mac application guidelines |
| watchOS | Apple Watch guidelines |
| visionOS | Apple Vision Pro spatial computing |
| tvOS | Apple TV guidelines |

## Notes

- Fetched from developer.apple.com/design/human-interface-guidelines
- Requires WKWebView crawling (JavaScript-rendered content)
- Always included in default search (not excluded like archive)
- Also available via the unified `search` MCP tool with `source: hig`
- Great for design decisions and App Store preparation
