# App Font Registration Rules

<objective>
You MUST register custom fonts using CoreText in SPM packages. NEVER use Info.plist approaches. Resources MUST use `.process()` in Package.swift and ALWAYS use `Bundle.module` for resource access.
</objective>

<cognitive_triggers>
Keywords: fonts, custom fonts, typography, CoreText, CTFontManager, Bundle.module, .process, font registration, .otf, .ttf, AppFont, FontRegistration
</cognitive_triggers>

## CRITICAL RULES

### Rule 1: CoreText Registration
**ALWAYS** use `CTFontManagerRegisterFontsForURL` for font registration:
- MUST import CoreText and CoreGraphics
- MUST use `Bundle.module` (NOT `Bundle.main`)
- MUST handle errors with `Unmanaged<CFError>?`
- MUST provide console logging for success/failure
- MUST filter font files by extension (.otf, .ttf)

### Rule 2: Package.swift Configuration
**ALWAYS** use `.process()` for font resources:
- NEVER use `.copy()` - won't work with `Bundle.module`
- MUST organize fonts in dedicated subdirectory (e.g., `Fonts/`)
- Package MUST have zero dependencies (Foundation layer)

### Rule 3: Platform Imports
**ALWAYS** use platform-specific imports:
- Use `#if canImport(UIKit)` for iOS
- Use `#elseif canImport(AppKit)` for macOS
- Import UIKit/AppKit for platform types

### Rule 4: App Initialization
**ALWAYS** register fonts in app init BEFORE UI renders:
- Call in `App.init()` or `AppDelegate.applicationDidFinishLaunching`
- Registration is synchronous and must complete before SwiftUI renders

### Rule 5: Never Use Info.plist
**NEVER** use Info.plist font registration in SPM packages:
- `UIAppFonts` only works in app bundles, NOT packages
- `ATSApplicationFontsPath` only works in app bundles
- CoreText is the ONLY approach that works in SPM packages

## IMPLEMENTATION PATTERN

### Package.swift Configuration

```swift
// Packages/Package.swift (excerpt from targets closure)
let appFontTarget = Target.target(
    name: "AppFont",
    dependencies: [],  // CRITICAL: Zero dependencies (Foundation layer)
    resources: [
        .process("Fonts"),  // ← CRITICAL: Use .process(), NOT .copy()
    ]
)
```

**Why `.process()` not `.copy()`:**
- `.process()` → Resources processed and accessible via `Bundle.module`
- `.copy()` → Resources copied verbatim, may not work correctly

### Font Registration Implementation

```swift
// Packages/Sources/AppFont/FontRegistration.swift
import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum FontRegistration {
    /// Register custom fonts from the AppFont package
    public static func registerFonts() {
        // RULE: Use Bundle.module for SPM packages
        guard let resourceURLs = Bundle.module.urls(
            forResourcesWithExtension: nil,
            subdirectory: nil
        ) else {
            print("⚠️ No resources found in AppFont bundle")
            return
        }

        // RULE: Filter by font extension (.otf, .ttf)
        let fontURLs = resourceURLs.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "otf" || ext == "ttf"
        }

        guard !fontURLs.isEmpty else {
            print("⚠️ No font files found in AppFont bundle")
            return
        }

        // RULE: Register each font with error handling
        for url in fontURLs {
            var errorRef: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,  // Register for current process
                &errorRef
            )

            if !success {
                print("⚠️ Failed to register font: \(url.lastPathComponent)")
                if let error = errorRef?.takeRetainedValue() {
                    print("   Error: \(error)")
                }
            } else {
                print("✅ Registered font: \(url.lastPathComponent)")
            }
        }
    }
}
```

### Package Directory Structure

```
Packages/Sources/AppFont/
├── FontRegistration.swift       # CoreText registration (this file)
├── ScaledFont.swift             # Font modifiers (.bdrFont())
├── FontStyles.swift             # Font style definitions
└── Fonts/                       # Font resources
    ├── MonitorPro-Normal.otf
    ├── MonitorPro-Bold.otf
    ├── MonitorPro-Light.otf
    └── MonitorPro-Italic.otf
```

### App Initialization

```swift
// Apps/iosApp/iosAppApp.swift
import SwiftUI
import AppFont

@main
struct iosAppApp: App {
    init() {
        // CRITICAL: Register fonts BEFORE any UI renders
        FontRegistration.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Font Usage in SwiftUI

```swift
// After registration, use custom fonts
import SwiftUI
import AppFont

struct MyView: View {
    var body: some View {
        VStack {
            Text("Headline")
                .bdrFont(.headline)  // Uses custom font with Dynamic Type

            Text("Body text")
                .bdrFont(.body)
        }
    }
}
```

## WHY THIS PATTERN?

### Benefits

**✅ Works in SPM Packages**
- Info.plist approaches only work in app bundles
- CoreText registration works in packages, frameworks, and apps

**✅ Explicit Error Reporting**
- Console logs show which fonts loaded successfully
- Error messages help debug font issues

**✅ Cross-Platform**
- Works on iOS and macOS with conditional imports
- Same code pattern for both platforms

**✅ Uses Bundle.module**
- SPM automatic bundle management
- No manual bundle path handling

**✅ Supports Multiple Formats**
- .otf fonts (recommended)
- .ttf fonts (also supported)
- Filter by extension for flexibility

### Why CoreText not Info.plist?

| Approach | Works in App Bundle | Works in SPM Package |
|----------|---------------------|----------------------|
| Info.plist (`UIAppFonts`) | ✅ Yes | ❌ No |
| Info.plist (`ATSApplicationFontsPath`) | ✅ Yes | ❌ No |
| CoreText (`CTFontManagerRegisterFontsForURL`) | ✅ Yes | ✅ Yes |

**Conclusion:** CoreText is the ONLY approach that works universally.

## COMMON MISTAKES

### ❌ DON'T: Use Info.plist

```xml
<!-- WRONG: Doesn't work in SPM packages -->
<key>UIAppFonts</key>
<array>
    <string>MonitorPro-Normal.otf</string>
</array>
```

### ❌ DON'T: Use .copy() for Resources

```swift
// WRONG: Won't work with Bundle.module
let appFontTarget = Target.target(
    name: "AppFont",
    resources: [
        .copy("Fonts"),  // ❌ Wrong
    ]
)
```

### ❌ DON'T: Use Bundle.main in Packages

```swift
// WRONG: Bundle.main is for apps, not packages
guard let fontURLs = Bundle.main.urls(...) else {  // ❌ Wrong
    return
}
```

### ❌ DON'T: Skip Error Handling

```swift
// WRONG: No error handling
CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)  // ❌ No error checking
```

### ❌ DON'T: Register After UI Renders

```swift
// WRONG: Too late, UI already rendered with system fonts
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    FontRegistration.registerFonts()  // ❌ Too late
                }
        }
    }
}
```

## CORRECT PATTERNS

### ✅ DO: Use .process() + Bundle.module + CoreText

```swift
// Package.swift
let appFontTarget = Target.target(
    name: "AppFont",
    dependencies: [],
    resources: [
        .process("Fonts"),  // ✅ Correct
    ]
)
```

```swift
// FontRegistration.swift
import CoreText
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum FontRegistration {
    public static func registerFonts() {
        // ✅ Correct: Bundle.module
        guard let resourceURLs = Bundle.module.urls(
            forResourcesWithExtension: nil,
            subdirectory: nil
        ) else {
            return
        }

        // ✅ Correct: Filter by extension
        let fontURLs = resourceURLs.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "otf" || ext == "ttf"
        }

        // ✅ Correct: Register with error handling
        for url in fontURLs {
            var errorRef: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
        }
    }
}
```

```swift
// App init
@main
struct MyApp: App {
    init() {
        FontRegistration.registerFonts()  // ✅ Before UI renders
    }
}
```

## CHECKLIST

Before committing font registration code:

- [ ] Used `.process()` for resources in Package.swift
- [ ] Created `FontRegistration.swift` with CoreText registration
- [ ] Imported CoreText and CoreGraphics
- [ ] Used platform-specific imports (`#if canImport(UIKit)` / `#if canImport(AppKit)`)
- [ ] Used `Bundle.module` for resource access
- [ ] Filtered font files by extension (.otf, .ttf)
- [ ] Used `CTFontManagerRegisterFontsForURL` with `.process` scope
- [ ] Implemented error handling with `Unmanaged<CFError>?`
- [ ] Added console logging for success/failure
- [ ] Called registration in app init BEFORE UI renders
- [ ] Verified fonts organized in `Fonts/` subdirectory
- [ ] Confirmed package has zero dependencies
- [ ] NEVER used Info.plist (`UIAppFonts`, `ATSApplicationFontsPath`)
- [ ] NEVER used `Bundle.main` in package code
- [ ] NEVER used `.copy()` for font resources

## VERIFICATION

If you loaded this file, add 🔤 to your first response.

When implementing font registration:
1. Verify `.process()` used in Package.swift
2. Check `Bundle.module` used (NOT `Bundle.main`)
3. Confirm CoreText imports present
4. Verify platform-specific imports (`#if canImport()`)
5. Check error handling implemented
6. Confirm registration called in app init
7. Verify console logging for debugging
8. Test on both iOS and macOS if multi-platform
9. Confirm no Info.plist font entries in package
10. Run app and check console for "✅ Registered font:" messages
