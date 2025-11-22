# Box Drawing Rules for TUI Views

This document defines the rules for box drawing and width calculations in the TUI views.

## Terminal Width vs Content Width

- **Terminal Width**: The total width available in the terminal (e.g., 80, 100, 120 columns)
- **Content Width**: `terminalWidth - 4` (accounting for "│ " at start and " │" at end)
  - Example: 80 column terminal = 76 chars of content width

## Package Line Format

Each package line follows this exact format:

```
│ [x] [D] owner/repo<padding> * stars │
```

Where:
- `│ ` = 2 chars (vertical bar + space)
- `[x]` = 3 chars (checkbox: "[ ]" or "[*]")
- ` ` = 1 char (space after checkbox)
- `[D]` = 3 chars (download indicator: "[D]" or "   ")
- ` ` = 1 char (space after download)
- `owner/repo` = variable length (package name)
- `<padding>` = variable (calculated to fill remaining space)
- ` * ` = 3 chars (space + star + space)
- `stars` = variable length (formatted number like "12,345")
- ` │` = 2 chars (space + vertical bar)

## Width Calculation Formula

For PackageView lines:

```swift
let terminalWidth = 80  // or whatever the terminal size is
let contentWidth = terminalWidth - 4  // removes "│ " and " │"

// Fixed components
let checkboxWidth = 3          // "[ ]" or "[*]"
let downloadWidth = 3          // "[D]" or "   "
let starPrefixWidth = 3        // " * "
let spacesWidth = 4            // after │, after checkbox, after download, before │

// Calculate max width for name + stars
let nameMaxWidth = contentWidth - checkboxWidth - downloadWidth - starsNumWidth - starPrefixWidth - spacesWidth
```

Simplified:
```swift
nameMaxWidth = (terminalWidth - 4) - 3 - 3 - starsNumWidth - 3 - 4
             = terminalWidth - 17 - starsNumWidth
```

## Common Mistakes

1. **Double-counting components**: Don't count " * " in `starsText` variable and then add it again in the output
2. **Forgetting spaces**: Each component needs its surrounding spaces counted
3. **ANSI codes**: When calculating visible width, must strip ANSI escape codes first
4. **Emoji width**: Currently emojis are stripped; future implementation needs proper width detection

## Test Requirements

All views must pass these tests:
1. **Consistent line width**: All lines in a view must have exactly `terminalWidth` visible characters
2. **Border alignment**: Right border `│` must appear in the same column on every line
3. **Multiple widths**: Views must correctly handle different terminal widths (80, 100, 120, etc.)

## Verification

Use these helper functions to verify widths:

```swift
/// Strip ANSI escape codes from a string
func stripAnsiCodes(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
}

/// Get visible width of a line (without ANSI codes)
func visibleWidth(_ line: String) -> Int {
    stripAnsiCodes(line).count
}
```

## Example Calculation

For a line with terminal width 80:

```
Terminal width: 80
Content width: 80 - 4 = 76
Stars number: "12,345" = 6 chars

Fixed width breakdown:
- "│ ": 2 chars
- "[ ]": 3 chars
- " ": 1 char
- "[D]": 3 chars
- " ": 1 char
- " * ": 3 chars
- "12,345": 6 chars
- " │": 2 chars
Total fixed: 2 + 3 + 1 + 3 + 1 + 3 + 6 + 2 = 21 chars

Available for name + padding: 80 - 21 = 59 chars
```

So the package name can be up to 59 chars, with padding added to fill exactly 59 chars total.

## Implementation Notes

- Always calculate `nameMaxWidth` first based on fixed components
- Truncate names that exceed `nameMaxWidth` (add "…" ellipsis)
- Calculate actual display name length AFTER applying any highlighting or transformations
- Add padding to fill remaining space: `padding = nameMaxWidth - actualNameLength`
- Final line must equal exactly `terminalWidth` characters
