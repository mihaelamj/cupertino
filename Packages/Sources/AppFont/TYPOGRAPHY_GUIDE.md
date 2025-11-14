# Typography Guide - G2XI App

## Font Family
**IBM Plex Sans** - Professional, accessible typeface designed by IBM for maximum legibility.

## Available Weights
- Thin
- ExtraLight
- Light
- Regular
- Text (slightly heavier than Regular)
- Medium
- SemiBold
- Bold

## Usage Guidelines

### 1. Page Titles (Bold)
```swift
Text("Your benefits")
    .bdrFont(.largeTitle, weight: .bold)
```
**Examples:** "Your benefits", "Climate money", "Add bank account", "Your Profile"

### 2. Section Headers (SemiBold)
```swift
Text("Persönliche Daten")
    .bdrFont(.title3, weight: .semibold)
```
**Examples:** "Persönliche Daten", "Zugeordnete Minderjährige", "Bankverbindungen", "Current credit balance"

### 3. Field Labels (Medium)
```swift
Text("IBAN")
    .bdrFont(.subheadline, weight: .medium)
```
**Examples:** "IBAN", "Name of the Bank", "Account holder", "Object of benefit"

### 4. Button Text (SemiBold)
```swift
Text("Log In")
    .bdrFont(.body, weight: .semibold)
```
**Examples:** "Log In", "Continue", "Save bank details", "Make a payout"

### 5. Body Text (Regular)
```swift
Text("Identity-based benefit payments")
    .bdrFont(.body)
```
**Examples:** Descriptions, support text, instructions

### 6. Large Numbers (Bold)
```swift
Text("130,00 €")
    .bdrFont(.largeTitle, weight: .bold)
```
**Examples:** Balance amounts, prominent financial figures

### 7. Small Text/Captions (Regular or Light)
```swift
Text("Do you have questions or need help?")
    .bdrFont(.caption)
```
**Examples:** Support text, secondary information, timestamps

### 8. Card Titles on Dark Backgrounds (SemiBold)
```swift
Text("Climate money")
    .bdrFont(.title2, weight: .semibold)
    .foregroundColor(.white)
```
**Examples:** Benefit card titles with image overlays

### 9. Values/Data (Regular)
```swift
Text("DE06 1001 1001 2621 3456 89")
    .bdrFont(.body)
```
**Examples:** IBAN numbers, bank names, user data

## Text Style Sizes

Based on iOS standard sizes:
- `.largeTitle` - 34pt (Page titles)
- `.title` - 28pt (Major sections)
- `.title2` - 22pt (Card titles)
- `.title3` - 20pt (Section headers)
- `.headline` - 17pt (Emphasized content)
- `.subheadline` - 15pt (Labels)
- `.body` - 17pt (Body text)
- `.callout` - 16pt (Calls to action)
- `.footnote` - 13pt (Secondary info)
- `.caption` - 12pt (Small text)
- `.caption2` - 11pt (Tiny text)

## Dark Mode Considerations

All font weights work identically in light and dark mode. Use semantic colors for text:
- `.textPrimary` - Main content
- `.textSecondary` - Supporting content
- `.textOnPrimary` - Text on black/primary backgrounds

## Accessibility

All fonts use Dynamic Type sizing (`.relativeTo:`) to scale with user accessibility settings. The font weights remain consistent regardless of text size.
