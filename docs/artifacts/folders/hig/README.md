# hig/ - Human Interface Guidelines

Apple Human Interface Guidelines from developer.apple.com/design/human-interface-guidelines.

## Location

**Default**: `~/.cupertino/hig/`

## Created By

```bash
cupertino fetch --type hig
```

## Structure

```
~/.cupertino/hig/
├── foundations/
│   ├── accessibility.md
│   ├── app-icons.md
│   ├── color.md
│   ├── dark-mode.md
│   ├── layout.md
│   ├── materials.md
│   ├── motion.md
│   ├── sf-symbols.md
│   ├── typography.md
│   └── ...
├── patterns/
│   ├── drag-and-drop.md
│   ├── entering-data.md
│   ├── file-management.md
│   ├── loading.md
│   ├── modality.md
│   ├── navigation.md
│   ├── onboarding.md
│   ├── searching.md
│   ├── settings.md
│   └── ...
├── components/
│   ├── buttons.md
│   ├── collections.md
│   ├── menus.md
│   ├── navigation-bars.md
│   ├── pickers.md
│   ├── progress-indicators.md
│   ├── segmented-controls.md
│   ├── sliders.md
│   ├── tab-bars.md
│   ├── text-fields.md
│   ├── toggles.md
│   └── ...
├── technologies/
│   ├── app-intents.md
│   ├── apple-pay.md
│   ├── carplay.md
│   ├── game-center.md
│   ├── healthkit.md
│   ├── homekit.md
│   ├── live-activities.md
│   ├── siri.md
│   ├── storekit.md
│   ├── widgets.md
│   └── ...
├── inputs/
│   ├── apple-pencil.md
│   ├── digital-crown.md
│   ├── game-controllers.md
│   ├── keyboards.md
│   ├── pointing-devices.md
│   ├── spatial-interactions.md
│   └── ...
└── platforms/
    ├── ios/
    ├── macos/
    ├── watchos/
    ├── visionos/
    └── tvos/
```

## Contents

### Category Folders
Each top-level folder represents a HIG category:
- **foundations/** - Core design principles
- **patterns/** - Common UX patterns
- **components/** - UI controls and views
- **technologies/** - Platform features and integrations
- **inputs/** - Input devices and methods
- **platforms/** - Platform-specific guidelines

### Markdown Files
- Converted from Apple's JavaScript-rendered HIG pages
- YAML front matter with metadata
- Full content preserved

### YAML Front Matter Example
```yaml
---
title: "Buttons"
category: "components"
platforms:
  - iOS
  - macOS
  - watchOS
  - visionOS
  - tvOS
source: hig
url: https://developer.apple.com/design/human-interface-guidelines/buttons
---
```

## Categories

| Category | Description | Examples |
|----------|-------------|----------|
| Foundations | Core design principles | Color, typography, icons, motion |
| Patterns | Common UX patterns | Navigation, onboarding, modality |
| Components | UI controls and views | Buttons, pickers, text fields |
| Technologies | Platform features | Siri, HealthKit, CarPlay |
| Inputs | Input methods | Touch, Apple Pencil, keyboard |

## Platforms

| Platform | Description |
|----------|-------------|
| iOS | iPhone and iPad guidelines |
| macOS | Mac application guidelines |
| watchOS | Apple Watch guidelines |
| visionOS | Apple Vision Pro guidelines |
| tvOS | Apple TV guidelines |

## Size

- **~200+ markdown files**
- **~20-50 MB total**

## Search Behavior

HIG documentation is **included in search by default** (unlike archive).

### Search All Documentation
```bash
cupertino search "buttons"
```

### Search HIG Only
```bash
cupertino search "navigation patterns" --source hig
```

### MCP Tool Usage
```json
{
  "name": "search",
  "arguments": {
    "query": "buttons",
    "source": "hig"
  }
}
```

The pre-#239 dedicated `search_hig` tool was unified into the single `search` tool with a `source` parameter. CLI equivalent: `cupertino search "buttons" --source hig`.

## Use Cases

- **Design decisions** - Understand Apple's design philosophy
- **Component guidelines** - Learn proper control usage
- **Platform conventions** - Match platform expectations
- **Accessibility** - Implement inclusive design
- **App Store preparation** - Meet design requirements

## Why HIG?

Human Interface Guidelines are essential for:
- Building apps that feel native on Apple platforms
- Understanding platform-specific design patterns
- Implementing accessible, inclusive interfaces
- Preparing apps for App Store review
- Making informed design decisions

## Notes

- Content requires WKWebView crawling (JavaScript-rendered)
- Guidelines updated regularly by Apple
- Some content varies by platform
- Great complement to API documentation
