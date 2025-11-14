# DemoAppFeature

Reference implementation showing BetaSettings integration.

> **Note**: This feature currently includes example code for backend integration, but the backend client modules have been removed from the project. The code is preserved as a reference for future implementation.

## Purpose

DemoAppFeature provides a working example of how to:
- Integrate BetaSettings into an app
- Display live settings information
- Observe and react to settings changes

## Current Status

The `DemoAppView` is wrapped in conditional compilation (`#if canImport(ApiClient)`) and will not compile until a backend client is implemented. It serves as documentation and reference code.

## Usage (when backend is available)

```swift
import DemoAppFeature

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            DemoAppView()
        }
    }
}
```

## What's Included

### 3 Tabs

**1. Home Tab**
- Current settings display
- Cache information (when enabled)
- Live status indicators

**2. Settings Tab**
- Full BetaSettingsView
- All configuration options
- Server environment picker
- Cache mode selector

**3. Debug Tab**
- Backend client status check
- All settings values (raw)
- Reset settings button

## Features

### Automatic Settings Sync

When you change any setting, it can be automatically applied to your backend client:

```swift
.onChange(of: settings.serverEnvironment) { _, _ in
    Task { try await settings.applyToBackend() }
}
```

**What gets synced**:
- Server Environment → Backend base URL
- Enable Caching → Caching middleware
- Cache Mode → Record vs Replay
- Debug Logging → Request/response logging

### Live Settings Display

Shows current values in a clean card layout:
- Environment
- Caching status
- Cache mode (if enabled)
- Timeout
- Debug logging
- Animation speed

## Use Cases

### 1. Reference Implementation

Study DemoAppView to learn:
- How to observe settings changes
- How to apply settings to a backend client
- How to display settings in UI
- How to handle errors

### 2. Development & Testing

Use DemoAppView during development to:
- Test BetaSettings integration
- Verify backend configuration
- Experiment with different settings

## Architecture

```
DemoAppView
    ├─ @State settings = BetaSettings.shared
    │
    ├─ Home Tab (read-only display)
    │   └─ Shows current values
    │
    ├─ Settings Tab
    │   └─ BetaSettingsView (editable)
    │
    └─ Debug Tab
        └─ Backend status + actions
```

**Automatic sync**:
```
User changes setting
    → onChange triggers
    → settings.applyToBackend()
    → Backend client reconfigures
    → Change takes effect
```

## Dependencies

- `BetaSettingsFeature` - Settings model + UI
- `SharedModels` - Common types (ServerEnvironment)
- `SwiftUI` - UI framework

## Platform Support

- iOS 18+
- macOS 15+

## See Also

- **BetaSettingsFeature/README.md** - Complete BetaSettings guide
