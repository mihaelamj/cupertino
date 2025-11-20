# How Box Drawing Tests Detect Subtle Bugs

## The Problem

Box drawing bugs are subtle because:
1. **ANSI codes are invisible** - Colors and formatting don't show character count
2. **State affects rendering** - Selected/highlighted lines may calculate width differently
3. **Edge cases hide** - Truncation, large numbers, special chars only show in specific scenarios
4. **Components interact** - A bug in one component (checkbox) affects total line width

## Detection Strategy

### 1. State Variation Tests (Detect ANSI Code Issues)

**What they catch:**
- ANSI color codes breaking width calculations
- Background colors adding unexpected characters
- Highlighting interfering with padding

**Tests:**
- `packageViewSelectedState` - Tests `[*]` vs `[ ]` with blue background
- `packageViewDownloadedState` - Tests `[D]` vs `   ` indicator
- `packageViewSearchHighlighting` - Tests yellow background on search matches
- `packageViewSearchHighlightingOnSelected` - Tests yellow text on blue background (nested ANSI)

**Example bug caught:**
```swift
// Bug: Adding background color but not stripping it when calculating padding
let displayName = Colors.bgYellow + "swift" + Colors.reset
let padding = nameMaxWidth - displayName.count  // WRONG! Counts ANSI codes
// Result: Line too long because padding calculation included color codes
```

### 2. Edge Case Tests (Detect Boundary Issues)

**What they catch:**
- Truncation logic errors
- Overflow with large numbers
- Minimum width handling

**Tests:**
- `packageViewLongNames` - Very long names + large star counts (123,456,789)
- `packageViewMinimumWidth` - Tests at minimum 80 column width
- `packageViewBorderAlignment` - Tests at 80, 100, 120 widths

**Example bug caught:**
```swift
// Bug: Not accounting for star count width when truncating name
let nameMaxWidth = contentWidth - 13  // Fixed components
let truncated = name.prefix(nameMaxWidth) + "…"
// Result: Line too long when star count is large (7+ digits)
// Fix: Must calculate: nameMaxWidth = contentWidth - fixedChars - starsNum.count
```

### 3. Component Validation Tests (Detect Formula Errors)

**What they catch:**
- Incorrect component widths
- Missing spaces
- Wrong formula constants

**Tests:**
- `packageViewComponentWidths` - Verifies presence of all components
- `packageViewLineWidth` - Multiple packages with different name lengths

**Example bug caught:**
```swift
// Bug: Forgetting to count spaces between components
let totalFixed = checkboxWidth + downloadWidth + starPrefixWidth  // Missing +4 for spaces!
// Result: Every line 4 chars too long
```

### 4. Consistency Tests (Detect Variability Bugs)

**What they catch:**
- Different packages rendering at different widths
- Conditional logic causing width variation
- State-dependent width changes

**Tests:**
- `packageViewLineWidth` - Short name (a/b) vs long name vs medium name
- `allViewsMatchWidth` - Every line in every view must be exact width

**Example bug caught:**
```swift
// Bug: Conditional padding only applied sometimes
if !packageName.isEmpty {
    padding = calculatePadding()  // Only pads non-empty names!
}
// Result: Empty package lines are wrong width
```

## How to Read Test Failures

### Failure: "Line should be 100 chars, got 103"
**Diagnosis:** Line is 3 chars too long
**Common causes:**
1. Not stripping ANSI codes before calculating padding
2. Forgot to count spaces between components
3. Added a component but didn't subtract from available width

### Failure: "Long name should contain ellipsis"
**Diagnosis:** Truncation not happening
**Common causes:**
1. Truncation threshold too high
2. Using wrong width variable
3. Truncation happens but "…" not added

### Failure: "Selected=true: Line should be 100 chars, got 98"
**Diagnosis:** Selected state miscalculates (2 chars short)
**Common causes:**
1. Stripping color codes from content before adding them
2. Different padding formula for highlighted lines
3. Missing re-application of background color after content

## Coverage Achieved

### Before New Tests: ~10%
- Basic smoke test only
- Would miss: state bugs, edge cases, component errors

### After New Tests: ~50%
**Now catches:**
- ✅ ANSI code width issues (4 tests)
- ✅ State variation bugs (4 tests)
- ✅ Edge cases (truncation, large numbers) (2 tests)
- ✅ Component presence and positioning (1 test)
- ✅ Multi-width consistency (1 test)
- ✅ Minimum width handling (1 test)

**Still missing:**
- Helper function unit tests (stripAnsiCodes, removeEmojis, renderPaddedLine)
- Border character validation (correct │├┤└┘┌┐─ used)
- Footer line specifics (metadata, page info)
- HomeView/LibraryView/SettingsView state variations
- Very large widths (200+ columns)
- Stats line truncation
- Help text with search mode vs normal mode

## When Tests Pass

**What it proves:**
1. All lines are exactly the expected width
2. Width is consistent across different:
   - Package name lengths
   - Star counts
   - States (selected, downloaded, highlighted)
   - Terminal widths (80, 100, 120)
3. Truncation works correctly for very long content
4. ANSI codes don't interfere with width calculations
5. All required components are present in output

**What it doesn't prove:**
- Visual appearance is correct (only width, not positioning)
- Performance is acceptable
- Accessibility for screen readers
- Works on all terminal emulators

## Recommended Test Addition Strategy

To reach 80% coverage, add in this order:

1. **Helper function tests** (High impact, easy to add)
   - Test `stripAnsiCodes` with various ANSI sequences
   - Test `removeEmojis` with edge cases
   - Test `renderPaddedLine` directly with different inputs

2. **Border character validation** (Prevents visual glitches)
   - Verify correct box drawing characters used
   - Check no ASCII fallback accidentally used

3. **Other view state tests** (Coverage gaps)
   - HomeView with different cursor positions and selected items
   - LibraryView with selected artifacts
   - SettingsView in edit mode

4. **Extreme edge cases** (Rare but possible)
   - Width < 80 (too narrow)
   - Width > 200 (very wide)
   - Package with no stars (0)
   - Package with billions of stars

## Summary

The new tests detect subtle bugs by:
1. **Testing all visual states** - Ensures ANSI codes don't break width
2. **Testing edge cases** - Catches overflow and truncation bugs
3. **Verifying components** - Ensures formula constants are correct
4. **Checking consistency** - Proves width doesn't vary unexpectedly

**Key insight:** Most box drawing bugs come from forgetting that ANSI codes add characters that shouldn't be counted. The tests strip ANSI before measuring, catching these bugs immediately.
