# Box Drawing Test Coverage Analysis

## Line Types in PackageView

1. **Border lines** (horizontal separators)
   - Top border: `┌` + `─` * (width-2) + `┐`
   - Middle separators: `├` + `─` * (width-2) + `┤`
   - Bottom border: `└` + `─` * (width-2) + `┘`

2. **Text lines** (via renderPaddedLine)
   - Title line
   - Stats line
   - Footer info lines (package name + page info)
   - Description line
   - Metadata line
   - Help text line

3. **Package entry lines** (via renderPackageLine)
   - Normal state
   - Selected state (highlighted)
   - Downloaded indicator
   - With search highlighting
   - With search highlighting + selected

4. **Empty filler lines**
   - `│` + spaces * (width-2) + `│`

## Scenarios to Test

### PackageView Scenarios
- [x] Lines with consistent width (different package name lengths)
- [x] Multiple terminal widths (80, 100, 120)
- [ ] **MISSING**: Selected vs unselected packages
- [ ] **MISSING**: Downloaded vs not downloaded packages
- [ ] **MISSING**: Search highlighting (yellow background)
- [ ] **MISSING**: Search highlighting + selection (yellow text on blue)
- [ ] **MISSING**: Very long package names (truncation with "…")
- [ ] **MISSING**: Very large star counts (affecting available name width)
- [ ] **MISSING**: Stats line with long search query (truncation)
- [ ] **MISSING**: Footer lines with ANSI colors
- [ ] **MISSING**: Empty state (no packages)
- [ ] **MISSING**: Single package
- [ ] **MISSING**: Page full of packages

### HomeView Scenarios
- [x] All lines match width
- [ ] **MISSING**: Different cursor positions (0, 1, 2)
- [ ] **MISSING**: Selected menu items (background color)
- [ ] **MISSING**: Stats with very large numbers
- [ ] **MISSING**: Stats formatting (KB, MB, GB)

### LibraryView Scenarios
- [x] All lines match width
- [ ] **MISSING**: Empty artifacts list
- [ ] **MISSING**: Single artifact
- [ ] **MISSING**: Multiple artifacts
- [ ] **MISSING**: Selected vs unselected artifacts
- [ ] **MISSING**: Very long artifact names (truncation)

### SettingsView Scenarios
- [x] All lines match width
- [ ] **MISSING**: Normal mode
- [ ] **MISSING**: Edit mode (with cursor █)
- [ ] **MISSING**: Selected vs unselected settings
- [ ] **MISSING**: Very long directory path (truncation)
- [ ] **MISSING**: Status message present
- [ ] **MISSING**: Read-only items

## Edge Cases to Test

### Width Calculations
- [ ] **MISSING**: Minimum width (what happens at 40 cols?)
- [ ] **MISSING**: Maximum width (200+ cols)
- [ ] **MISSING**: Width with ANSI codes in content
- [ ] **MISSING**: Width with truncated content ("...")

### Special Characters
- [ ] **MISSING**: Package names with special chars (-, _, /)
- [ ] **MISSING**: Descriptions with special chars
- [ ] **MISSING**: Numbers with thousand separators (12,345)

### Border Alignment
- [x] Right border `│` aligns across all lines
- [ ] **MISSING**: Border characters are correct type (┌┐├┤└┘─│)
- [ ] **MISSING**: No gaps or overlaps in borders

## Component-Level Tests Needed

### renderPackageLine Function
- [ ] **MISSING**: Test fixed component widths:
  - checkbox: exactly 3 chars
  - download indicator: exactly 3 chars
  - star prefix " * ": exactly 3 chars
  - borders "│ " and " │": exactly 4 chars total
- [ ] **MISSING**: Test padding calculation
- [ ] **MISSING**: Test name truncation with different star counts

### renderPaddedLine Function
- [ ] **MISSING**: Text shorter than contentWidth
- [ ] **MISSING**: Text longer than contentWidth (should truncate with "...")
- [ ] **MISSING**: Text with ANSI codes
- [ ] **MISSING**: Empty text
- [ ] **MISSING**: contentWidth calculation (width - 4)

### stripAnsiCodes Function
- [ ] **MISSING**: String with no ANSI codes
- [ ] **MISSING**: String with color codes
- [ ] **MISSING**: String with multiple ANSI codes
- [ ] **MISSING**: String with nested ANSI codes

### TextSanitizer.removeEmojis Function
- [ ] **MISSING**: String with no emojis
- [ ] **MISSING**: String with emojis
- [ ] **MISSING**: String with only emojis
- [ ] **MISSING**: Mixed ASCII and emoji

## Current Test Coverage: ~10%

### Tests Present:
1. packageViewLineWidth - basic consistency check
2. packageViewBorderAlignment - width at different sizes
3. allViewsMatchWidth - all views at one width

### Tests Missing: ~30 additional test cases needed

## Priority Tests to Add (High Impact)

1. **Package line component width test** - Verify each component is exact size
2. **Search highlighting width test** - Yellow background shouldn't affect width
3. **Selection highlighting width test** - Blue background shouldn't affect width
4. **Truncation test** - Very long names should truncate correctly
5. **Empty vs full page test** - Filler lines should have correct width
6. **Stats line truncation test** - Long search query should truncate
7. **Border character test** - Verify correct box drawing chars used
8. **renderPaddedLine unit test** - Test the core padding logic directly
9. **stripAnsiCodes unit test** - Verify ANSI code removal
10. **Large number formatting test** - Verify star counts don't break layout

## Conclusion

Current tests provide basic smoke testing but miss:
- **State variations** (selected, highlighted, downloaded)
- **Edge cases** (truncation, very large/small widths)
- **Component-level validation** (individual function tests)
- **Special character handling** (ANSI codes, emojis, numbers)

**Estimated coverage: 10-15% of scenarios tested**
**Target coverage: 80%+ for production readiness**
