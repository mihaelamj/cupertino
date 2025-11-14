# App Colors Architecture Rules

<objective>
You MUST create AppColors as a separate package with HSV-based color management, dynamic light/dark mode support, and semantic color naming. AppColors MUST be independent from AppTheme, which combines AppColors + AppFonts.
</objective>

<cognitive_triggers>
Keywords: colors, AppColors, HSV, HSB, dynamic colors, light mode, dark mode, Color extension, semantic colors, brandPrimary, textPrimary, bgPrimary, UIColor, NSColor, appearance
</cognitive_triggers>

## CRITICAL RULES

### Rule 1: Package Structure
**ALWAYS** structure colors as separate packages:
- **AppColors** - Standalone color system (zero dependencies)
- **AppFonts** - Standalone font system (zero dependencies)
- **AppTheme** - Combines AppColors + AppFonts

### Rule 2: HSV Internal Representation
**ALWAYS** use HSV (Hue, Saturation, Value) internally:
- Store all colors as HSV components
- Calculate dark/light variants using HSV manipulation
- Convert to/from RGB when needed for SwiftUI Color

### Rule 3: Semantic Color Names (Apple Standard)
**ALWAYS** use these exact semantic color names (following Apple HIG):
- `primary` - Primary brand/action color (like systemBlue)
- `success` - Success states (like systemGreen)
- `secondary` - Secondary brand color (like systemPurple)
- `destructive` - Destructive/error actions (like systemRed) - Apple uses "destructive" NOT "danger"
- `label` - Primary text color (like UIColor.label)
- `secondaryLabel` - Secondary text color (like UIColor.secondaryLabel)
- `onPrimary` - Text on primary colored backgrounds
- `background` - Primary background (like systemBackground)
- `secondaryBackground` - Secondary/elevated background (like secondarySystemBackground)

### Rule 4: Dynamic Color Support
**ALWAYS** create dynamic colors that adapt to appearance:
- Use UIColor dynamic colors on iOS
- Use NSColor dynamic colors on macOS
- Fallback to light variant on other platforms

### Rule 5: Initialization Modes
**ALWAYS** support two initialization modes:
1. **Explicit colors** - User provides light and dark variants
2. **System fallback** - Use system colors as defaults

## PACKAGE ARCHITECTURE

### Package Hierarchy

```
AppColors (standalone - zero dependencies)
    ↓
AppFonts (standalone - zero dependencies)
    ↓
AppTheme (combines AppColors + AppFonts)
```

### AppColors Package Structure

```
Packages/Sources/AppColors/
├── HSVColor.swift                 # HSV color representation
├── Color+Dynamic.swift            # Dynamic color extension
├── Color+HSV.swift                # HSV conversion utilities
├── AppColors.swift                # Main semantic colors
├── SystemColorDefaults.swift     # System color fallbacks
└── README.md                      # Usage documentation
```

### Package.swift Configuration

```swift
// Packages/Package.swift (excerpt from targets closure)

// ---------- Foundation Layer ----------
let appColorsTarget = Target.target(
    name: "AppColors",
    dependencies: []  // CRITICAL: Zero dependencies
)

let appFontsTarget = Target.target(
    name: "AppFonts",
    dependencies: [],
    resources: [
        .process("Fonts"),
    ]
)

let appThemeTarget = Target.target(
    name: "AppTheme",
    dependencies: [
        "AppColors",  // Color system
        "AppFonts",   // Font system
    ]
)
```

## IMPLEMENTATION PATTERNS

### 1. HSV Color Representation

```swift
// Packages/Sources/AppColors/HSVColor.swift
import SwiftUI

/// Internal HSV color representation for manipulation
public struct HSVColor: Equatable, Sendable {
    /// Hue (0.0 - 1.0)
    public let hue: Double

    /// Saturation (0.0 - 1.0)
    public let saturation: Double

    /// Value/Brightness (0.0 - 1.0)
    public let value: Double

    /// Alpha/Opacity (0.0 - 1.0)
    public let alpha: Double

    public init(hue: Double, saturation: Double, value: Double, alpha: Double = 1.0) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.alpha = alpha
    }

    /// Convert to SwiftUI Color
    public func toColor() -> Color {
        Color(hue: hue, saturation: saturation, brightness: value, opacity: alpha)
    }

    /// Calculate dark mode variant
    /// Reduces brightness and slightly increases saturation
    public func darkVariant() -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: min(1.0, saturation * 1.1),  // Slightly more saturated
            value: max(0.15, value * 0.6),           // Darker (60% of original)
            alpha: alpha
        )
    }

    /// Calculate light mode variant
    /// Increases brightness and slightly reduces saturation
    public func lightVariant() -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: max(0.0, saturation * 0.85),  // Slightly less saturated
            value: min(1.0, value * 1.3),             // Brighter (130% of original)
            alpha: alpha
        )
    }

    /// Adjust brightness by factor
    public func adjustingValue(by factor: Double) -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: saturation,
            value: min(1.0, max(0.0, value * factor)),
            alpha: alpha
        )
    }

    /// Adjust saturation by factor
    public func adjustingSaturation(by factor: Double) -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: min(1.0, max(0.0, saturation * factor)),
            value: value,
            alpha: alpha
        )
    }
}
```

### 2. Color + HSV Extension

```swift
// Packages/Sources/AppColors/Color+HSV.swift
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Initialize from HSV color
    public init(hsv: HSVColor) {
        self = hsv.toColor()
    }

    /// Convert Color to HSV representation
    public func toHSV() -> HSVColor {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return HSVColor(
            hue: Double(hue),
            saturation: Double(saturation),
            value: Double(brightness),
            alpha: Double(alpha)
        )
        #elseif canImport(AppKit)
        let nsColor = NSColor(self)
        let converted = nsColor.usingColorSpace(.deviceRGB) ?? nsColor

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return HSVColor(
            hue: Double(hue),
            saturation: Double(saturation),
            value: Double(brightness),
            alpha: Double(alpha)
        )
        #else
        // Fallback for other platforms
        return HSVColor(hue: 0, saturation: 0, value: 0.5, alpha: 1.0)
        #endif
    }
}
```

### 3. Dynamic Color Extension

```swift
// Packages/Sources/AppColors/Color+Dynamic.swift
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Creates dynamic color that adapts to appearance
    public init(light: Color, dark: Color) {
        #if os(iOS)
        self = Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self = Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }

    /// Creates dynamic color from HSV, automatically calculating dark variant
    public init(lightHSV: HSVColor) {
        let lightColor = lightHSV.toColor()
        let darkColor = lightHSV.darkVariant().toColor()
        self.init(light: lightColor, dark: darkColor)
    }

    /// Creates dynamic color from HSV, automatically calculating light variant
    public init(darkHSV: HSVColor) {
        let darkColor = darkHSV.toColor()
        let lightColor = darkHSV.lightVariant().toColor()
        self.init(light: lightColor, dark: darkColor)
    }
}
```

### 4. System Color Defaults

```swift
// Packages/Sources/AppColors/SystemColorDefaults.swift
import SwiftUI

/// System color defaults for fallback (Apple HIG inspired)
public enum SystemColorDefaults {
    /// Primary action color (like systemBlue)
    public static let primary = HSVColor(
        hue: 0.58,      // Blue hue
        saturation: 0.8,
        value: 0.9,
        alpha: 1.0
    )

    /// Success state color (like systemGreen)
    public static let success = HSVColor(
        hue: 0.33,      // Green hue
        saturation: 0.7,
        value: 0.8,
        alpha: 1.0
    )

    /// Secondary brand color (like systemPurple)
    public static let secondary = HSVColor(
        hue: 0.75,      // Purple hue
        saturation: 0.6,
        value: 0.85,
        alpha: 1.0
    )

    /// Destructive action color (like systemRed)
    public static let destructive = HSVColor(
        hue: 0.0,       // Red hue
        saturation: 0.8,
        value: 0.9,
        alpha: 1.0
    )

    /// Primary text color (like UIColor.label)
    public static let label = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 0.1,     // Very dark gray (light mode)
        alpha: 1.0
    )

    /// Secondary text color (like UIColor.secondaryLabel)
    public static let secondaryLabel = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 0.5,     // Medium gray
        alpha: 1.0
    )

    /// Text on primary colored backgrounds
    public static let onPrimary = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 1.0,     // White
        alpha: 1.0
    )

    /// Primary background (like systemBackground)
    public static let background = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 1.0,     // White (light mode)
        alpha: 1.0
    )

    /// Secondary background (like secondarySystemBackground)
    public static let secondaryBackground = HSVColor(
        hue: 0.0,
        saturation: 0.0,
        value: 0.95,    // Light gray
        alpha: 1.0
    )
}
```

### 5. AppColors Main Structure

```swift
// Packages/Sources/AppColors/AppColors.swift
import SwiftUI

/// Semantic color palette for the application (Apple HIG standard)
public struct AppColors: Sendable {
    // MARK: - Semantic Colors

    /// Primary brand/action color (like systemBlue)
    public let primary: Color

    /// Success state color (like systemGreen)
    public let success: Color

    /// Secondary brand color (like systemPurple)
    public let secondary: Color

    /// Destructive/error action color (like systemRed)
    public let destructive: Color

    // MARK: - Text Colors

    /// Primary text color (like UIColor.label)
    public let label: Color

    /// Secondary text color (like UIColor.secondaryLabel)
    public let secondaryLabel: Color

    /// Text color for use on primary colored backgrounds
    public let onPrimary: Color

    // MARK: - Background Colors

    /// Primary background color (like systemBackground)
    public let background: Color

    /// Secondary background color (like secondarySystemBackground)
    public let secondaryBackground: Color

    // MARK: - Initialization

    /// Initialize with explicit HSV colors for light mode
    /// Dark mode variants will be calculated automatically
    public init(
        primaryHSV: HSVColor,
        successHSV: HSVColor,
        secondaryHSV: HSVColor,
        destructiveHSV: HSVColor,
        labelHSV: HSVColor,
        secondaryLabelHSV: HSVColor,
        onPrimaryHSV: HSVColor,
        backgroundHSV: HSVColor,
        secondaryBackgroundHSV: HSVColor
    ) {
        self.primary = Color(lightHSV: primaryHSV)
        self.success = Color(lightHSV: successHSV)
        self.secondary = Color(lightHSV: secondaryHSV)
        self.destructive = Color(lightHSV: destructiveHSV)
        self.label = Color(lightHSV: labelHSV)
        self.secondaryLabel = Color(lightHSV: secondaryLabelHSV)
        self.onPrimary = Color(lightHSV: onPrimaryHSV)
        self.background = Color(lightHSV: backgroundHSV)
        self.secondaryBackground = Color(lightHSV: secondaryBackgroundHSV)
    }

    /// Initialize with explicit light and dark Color pairs
    public init(
        primary: (light: Color, dark: Color),
        success: (light: Color, dark: Color),
        secondary: (light: Color, dark: Color),
        destructive: (light: Color, dark: Color),
        label: (light: Color, dark: Color),
        secondaryLabel: (light: Color, dark: Color),
        onPrimary: (light: Color, dark: Color),
        background: (light: Color, dark: Color),
        secondaryBackground: (light: Color, dark: Color)
    ) {
        self.primary = Color(light: primary.light, dark: primary.dark)
        self.success = Color(light: success.light, dark: success.dark)
        self.secondary = Color(light: secondary.light, dark: secondary.dark)
        self.destructive = Color(light: destructive.light, dark: destructive.dark)
        self.label = Color(light: label.light, dark: label.dark)
        self.secondaryLabel = Color(light: secondaryLabel.light, dark: secondaryLabel.dark)
        self.onPrimary = Color(light: onPrimary.light, dark: onPrimary.dark)
        self.background = Color(light: background.light, dark: background.dark)
        self.secondaryBackground = Color(light: secondaryBackground.light, dark: secondaryBackground.dark)
    }

    // MARK: - System Default

    /// Default color palette using system colors
    public static let system = AppColors(
        primaryHSV: SystemColorDefaults.primary,
        successHSV: SystemColorDefaults.success,
        secondaryHSV: SystemColorDefaults.secondary,
        destructiveHSV: SystemColorDefaults.destructive,
        labelHSV: SystemColorDefaults.label,
        secondaryLabelHSV: SystemColorDefaults.secondaryLabel,
        onPrimaryHSV: SystemColorDefaults.onPrimary,
        backgroundHSV: SystemColorDefaults.background,
        secondaryBackgroundHSV: SystemColorDefaults.secondaryBackground
    )
}

// MARK: - Environment Key

private struct AppColorsKey: EnvironmentKey {
    static let defaultValue = AppColors.system
}

extension EnvironmentValues {
    /// Access app colors from environment
    public var appColors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }
}

extension View {
    /// Set custom app colors for this view hierarchy
    public func appColors(_ colors: AppColors) -> some View {
        environment(\.appColors, colors)
    }
}
```

### 6. AppTheme Package (Combines AppColors + AppFonts)

```swift
// Packages/Sources/AppTheme/AppTheme.swift
import SwiftUI
import AppColors
import AppFont

/// Complete theme combining colors and typography
public struct AppTheme: Sendable {
    public let colors: AppColors

    // Font-related properties can be added here if needed
    // For now, fonts are accessed directly via AppFont package

    public init(colors: AppColors = .system) {
        self.colors = colors
    }

    /// Default system theme
    public static let system = AppTheme(colors: .system)
}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.system
}

extension EnvironmentValues {
    /// Access app theme from environment
    public var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    /// Set custom app theme for this view hierarchy
    public func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
    }
}
```

## USAGE PATTERNS

### Basic Usage with System Colors

```swift
import SwiftUI
import AppColors

struct MyView: View {
    @Environment(\.appColors) var colors

    var body: some View {
        VStack {
            Text("Primary Text")
                .foregroundColor(colors.label)

            Button("Action") {
                // ...
            }
            .foregroundColor(colors.onPrimary)
            .background(colors.primary)
        }
        .background(colors.background)
    }
}
```

### Custom Brand Colors

```swift
import SwiftUI
import AppColors

// Define your brand colors in HSV
let customColors = AppColors(
    primaryHSV: HSVColor(hue: 0.6, saturation: 0.85, value: 0.95),
    successHSV: HSVColor(hue: 0.33, saturation: 0.7, value: 0.8),
    secondaryHSV: HSVColor(hue: 0.75, saturation: 0.6, value: 0.85),
    destructiveHSV: HSVColor(hue: 0.0, saturation: 0.8, value: 0.9),
    labelHSV: HSVColor(hue: 0, saturation: 0, value: 0.1),
    secondaryLabelHSV: HSVColor(hue: 0, saturation: 0, value: 0.5),
    onPrimaryHSV: HSVColor(hue: 0, saturation: 0, value: 1.0),
    backgroundHSV: HSVColor(hue: 0, saturation: 0, value: 1.0),
    secondaryBackgroundHSV: HSVColor(hue: 0, saturation: 0, value: 0.95)
)

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .appColors(customColors)
        }
    }
}
```

### Explicit Light/Dark Pairs

```swift
import SwiftUI
import AppColors

let customColors = AppColors(
    primary: (
        light: Color(red: 0.2, green: 0.4, blue: 0.8),
        dark: Color(red: 0.3, green: 0.5, blue: 0.9)
    ),
    success: (
        light: Color(red: 0.2, green: 0.8, blue: 0.3),
        dark: Color(red: 0.3, green: 0.9, blue: 0.4)
    ),
    secondary: (
        light: Color(red: 0.5, green: 0.3, blue: 0.8),
        dark: Color(red: 0.6, green: 0.4, blue: 0.9)
    ),
    destructive: (
        light: Color(red: 0.8, green: 0.2, blue: 0.2),
        dark: Color(red: 0.9, green: 0.3, blue: 0.3)
    ),
    label: (
        light: Color(white: 0.1),
        dark: Color(white: 0.9)
    ),
    secondaryLabel: (
        light: Color(white: 0.5),
        dark: Color(white: 0.7)
    ),
    onPrimary: (
        light: .white,
        dark: .white
    ),
    background: (
        light: .white,
        dark: Color(white: 0.1)
    ),
    secondaryBackground: (
        light: Color(white: 0.95),
        dark: Color(white: 0.15)
    )
)
```

### Using AppTheme

```swift
import SwiftUI
import AppTheme
import AppColors
import AppFont

@main
struct MyApp: App {
    init() {
        // Register fonts
        FontRegistration.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appTheme(AppTheme.system)
        }
    }
}

struct MyView: View {
    @Environment(\.appTheme) var theme

    var body: some View {
        Text("Hello")
            .foregroundColor(theme.colors.label)  // Apple-style naming
            .bdrFont(.headline)  // From AppFont
    }
}
```

## COMMON MISTAKES

### ❌ DON'T: Make AppColors depend on AppFonts

```swift
// WRONG: AppColors with font dependencies
let appColorsTarget = Target.target(
    name: "AppColors",
    dependencies: [
        "AppFonts",  // ❌ AppColors must be standalone
    ]
)
```

### ❌ DON'T: Use RGB for internal representation

```swift
// WRONG: Storing colors as RGB
public struct AppColors {
    let brandPrimary: (r: Double, g: Double, b: Double)  // ❌ Use HSV
}
```

### ❌ DON'T: Hardcode dark mode colors

```swift
// WRONG: Manually defining every dark variant
self.brandPrimary = Color(light: .blue, dark: .cyan)  // ❌ Calculate from HSV
```

### ❌ DON'T: Skip dynamic color support

```swift
// WRONG: Static color that doesn't adapt
public let brandPrimary: Color = .blue  // ❌ Won't adapt to dark mode
```

### ❌ DON'T: Use non-semantic names

```swift
// WRONG: Non-semantic naming
public let blue: Color        // ❌ Use primary
public let lightGray: Color   // ❌ Use secondaryBackground
public let red: Color         // ❌ Use destructive
```

### ❌ DON'T: Use Google Material Design naming

```swift
// WRONG: Using Material Design (we follow Apple HIG)
public let error: Color       // ❌ Apple uses "destructive"
public let onSurface: Color   // ❌ Apple uses "label"
public let surface: Color     // ❌ Apple uses "background"/"secondaryBackground"
```

## CORRECT PATTERNS

### ✅ DO: Standalone Packages

```swift
// AppColors (zero dependencies)
let appColorsTarget = Target.target(
    name: "AppColors",
    dependencies: []  // ✅ Standalone
)

// AppFonts (zero dependencies)
let appFontsTarget = Target.target(
    name: "AppFonts",
    dependencies: [],
    resources: [.process("Fonts")]
)

// AppTheme (combines both)
let appThemeTarget = Target.target(
    name: "AppTheme",
    dependencies: [
        "AppColors",  // ✅ Uses both
        "AppFonts",
    ]
)
```

### ✅ DO: HSV Internal Representation

```swift
// ✅ Store and manipulate in HSV
public struct HSVColor {
    let hue: Double
    let saturation: Double
    let value: Double
    let alpha: Double

    func darkVariant() -> HSVColor {
        HSVColor(
            hue: hue,
            saturation: min(1.0, saturation * 1.1),
            value: max(0.15, value * 0.6),
            alpha: alpha
        )
    }
}
```

### ✅ DO: Apple-Style Semantic Naming

```swift
// ✅ Apple HIG semantic color names
public struct AppColors {
    public let primary: Color         // Like systemBlue
    public let destructive: Color     // Like systemRed (NOT "danger" or "error")
    public let label: Color           // Like UIColor.label
    public let background: Color      // Like systemBackground
    // ...
}
```

### ✅ DO: Dynamic Colors

```swift
// ✅ Dynamic color that adapts
public init(light: Color, dark: Color) {
    #if os(iOS)
    self = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
    #elseif os(macOS)
    self = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
    })
    #else
    self = light
    #endif
}
```

## CHECKLIST

Before committing color system code:

- [ ] AppColors package exists as standalone (zero dependencies)
- [ ] AppFonts package exists as standalone (zero dependencies)
- [ ] AppTheme package combines AppColors + AppFonts
- [ ] HSVColor struct defined with hue, saturation, value, alpha
- [ ] HSVColor has darkVariant() and lightVariant() methods
- [ ] Color+Dynamic extension implements init(light:dark:)
- [ ] Color+HSV extension converts between Color and HSVColor
- [ ] AppColors struct has all 9 semantic colors (Apple HIG naming)
- [ ] Used `destructive` (NOT "danger" or "error") - Apple standard
- [ ] Used `label` and `secondaryLabel` (NOT "textPrimary") - Apple standard
- [ ] Used `background` and `secondaryBackground` (NOT "bgPrimary") - Apple standard
- [ ] SystemColorDefaults provides fallback values
- [ ] AppColors has init with HSV colors
- [ ] AppColors has init with explicit light/dark pairs
- [ ] AppColors.system static property exists
- [ ] Environment key for appColors implemented
- [ ] Environment key for appTheme implemented
- [ ] Platform-specific dynamic colors (#if os(iOS) / os(macOS))
- [ ] All color names follow Apple HIG (no "blue", "red", "error", "danger", etc.)

## VERIFICATION

If you loaded this file, add 🎨 to your first response.

When implementing color system:
1. Verify AppColors is standalone package
2. Check HSV internal representation
3. Confirm all 9 semantic colors present
4. Verify dynamic color extension with platform conditionals
5. Check light/dark variant calculation in HSVColor
6. Confirm AppTheme depends on AppColors + AppFonts
7. Test color adaptation in light and dark mode
8. Verify system default colors work
9. Test custom color initialization
10. Check environment key integration
