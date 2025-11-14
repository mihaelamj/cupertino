# BetaSettingsFeature

A simple, protocol-based beta settings package for iOS and macOS.

## Quick Start

```swift
import BetaSettingsFeature

// Simple app with settings
struct MyApp: View {
    var body: some View {
        BetaSettingsView()
    }
}

// Access settings programmatically
let env = BetaSettings.shared.serverEnvironment
```

## Features

- ✅ **@Observable** - Modern Swift observation
- ✅ **Protocol-based** - Testable with MockBetaSettings
- ✅ **Auto-persistence** - UserDefaults via didSet
- ✅ **Cross-platform** - iOS 18+ and macOS 15+
- ✅ **Zero dependencies** - Pure SwiftUI

## Current Settings (8)

### API Configuration
- **Server Environment** - `.local`, `.staging`, `.production`
- **Enable Caching** - `Bool` - Enable/disable response caching
- **Cache Mode** - `.record` or `.replay` (VCR-style)
- **Request Timeout** - `Double` (5-120 seconds)

### Debugging
- **Debug Logging** - `Bool`
- **Verbose Mode** - `Bool` (requires restart)

### Performance
- **Animation Speed** - `Double` (0.5x - 2.0x)
- **Reduce Motion** - `Bool`

---

# Table of Contents

1. [Usage](#usage)
2. [Adding Settings](#adding-settings)
3. [Architecture](#architecture)
4. [Testing](#testing)

---

# Usage

## Basic Usage

### 1. Display Settings UI

```swift
import BetaSettingsFeature

TabView {
    BetaSettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
}
```

### 2. Access Settings

```swift
// Read
let env = BetaSettings.shared.serverEnvironment
let caching = BetaSettings.shared.enableCaching

// Write (auto-persisted)
BetaSettings.shared.serverEnvironment = .staging
BetaSettings.shared.enableCaching = true
```

### 3. Observe Changes

```swift
struct FeatureView: View {
    @State private var settings = BetaSettings.shared

    var body: some View {
        Text("Environment: \(settings.serverEnvironment.displayName)")
            .onChange(of: settings.serverEnvironment) { _, new in
                print("Changed to: \(new)")
            }
    }
}
```

---

# Adding Settings

Add in **3 places**:

## 1. Model (BetaSettings.swift)

```swift
/// New feature flag
public var enableNewFeature: Bool = false {
    didSet {
        UserDefaults.standard.set(enableNewFeature, forKey: Keys.enableNewFeature)
    }
}

// In init():
self.enableNewFeature = UserDefaults.standard.bool(forKey: Keys.enableNewFeature)

// In resetToDefaults():
enableNewFeature = false

// In Keys enum:
static let enableNewFeature = "betaSettings.enableNewFeature"
```

## 2. View (BetaSettingsView.swift)

```swift
Toggle("Enable New Feature", isOn: $settings.enableNewFeature)
```

## 3. Protocol (BetaSettings.swift)

```swift
// In BetaSettingsProtocol:
var enableNewFeature: Bool { get set }

// In MockBetaSettings:
public var enableNewFeature: Bool = false
```

---

# Architecture

## Overview

The BetaSettings feature provides a clean, maintainable system for managing application configuration settings.

## Pattern

**@Observable Singleton + UserDefaults + Protocol**

```
BetaSettings (Model)          BetaSettingsView (UI)
    @Observable          →        @State
    didSet persistence   ←        Bindings ($settings)
         ↓
   UserDefaults
```

## Key Design Principles

### 1. Single Source of Truth for Server Environments

**Location**: `SharedModels/ServerEnvironment.swift`

```swift
public enum ServerEnvironment: String, Codable, CaseIterable {
    case local
    case staging
    case production
}
```

**Why SharedModels?**
- Zero dependencies - pure model layer
- Can be used by both UI configuration and backend clients
- No hardcoded URLs - just the environment identifier

### 2. BetaSettings Owns User Configuration

**Location**: `BetaSettingsFeature/BetaSettings.swift`

**Responsibilities**:
- User-facing settings (environment selection, caching, timeouts, etc.)
- UserDefaults persistence via `didSet`
- @Observable pattern for SwiftUI binding

## Package Dependencies

```
┌─────────────────┐
│  SharedModels   │  ← Base layer (no dependencies)
│  - ServerEnvironment (enum only)
└─────────────────┘
         ↑
         │
┌────────┴──────────────┐
│ BetaSettingsFeature   │
│ - BetaSettings        │
│ - UI                  │
└───────────────────────┘
```

## How It Works

### 1. User Changes Environment in Settings

```swift
// BetaSettingsView.swift
Picker("Server Environment", selection: $settings.serverEnvironment) {
    ForEach(ServerEnvironment.allCases) { env in
        Text(env.displayName).tag(env)
    }
}
```

### 2. Setting Is Persisted

```swift
// BetaSettings.swift
public var serverEnvironment: ServerEnvironment = .production {
    didSet {
        UserDefaults.standard.set(serverEnvironment.rawValue,
                                  forKey: Keys.serverEnvironment)
    }
}
```

### 3. Your App Uses the Setting

```swift
// In your app
let selectedEnv = BetaSettings.shared.serverEnvironment
// Use this to configure your backend client
```

## Persistence

```swift
// 1. Property with default + didSet
public var setting: Bool = false {
    didSet {
        UserDefaults.standard.set(setting, forKey: Keys.setting)
    }
}

// 2. Load in init()
private init() {
    self.setting = UserDefaults.standard.bool(forKey: Keys.setting)
    // Triggers didSet (harmless redundancy)
}

// 3. Changes auto-save
BetaSettings.shared.setting = true  // ← persisted automatically
```

## Thread Safety

- All access is `@MainActor` isolated
- Safe from SwiftUI views
- Observable pattern ensures UI updates
- Background threads: use `await MainActor.run { }`

## Benefits of This Architecture

1. **Separation of Concerns**
   - SharedModels: Pure data models
   - BetaSettings: User configuration

2. **Type Safety**
   - Enum-based environment selection
   - Compile-time checking of environment cases

3. **Testability**
   - MockBetaSettings for testing UI
   - Environment switching logic is isolated

4. **Maintainability**
   - Add new settings without touching other modules
   - Add new environments by adding enum cases

---

# Testing

```swift
import XCTest
@testable import BetaSettingsFeature

@MainActor
final class SettingsTests: XCTestCase {
    func testMockSettings() {
        let mock = MockBetaSettings()
        mock.serverEnvironment = .local
        mock.enableCaching = true

        XCTAssertEqual(mock.serverEnvironment, .local)
        XCTAssertTrue(mock.enableCaching)
    }
}
```

---

# Build

```bash
swift build --target BetaSettingsFeature
```
