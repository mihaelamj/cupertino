# Constants Refactoring Report

*Date: 2024-11-16*
*Status: Audit of hardcoded values that need refactoring to Constants.swift*

---

## Summary

**Status:** Most constants are already refactored, but several magic numbers and hardcoded values remain

**Found:**
- ✅ **Good:** URL constants, file names, directory names already use Constants.swift
- ❌ **Needs Refactoring:** Magic numbers (delays, intervals, limits)
- ❌ **Needs Refactoring:** Hardcoded HTTP headers in some places
- ❌ **Needs Refactoring:** Rate limiting intervals

---

## Hardcoded Values That Need Refactoring

### 1. Sleep/Delay Intervals

#### SwiftEvolutionCrawler.swift:60
```swift
try await Task.sleep(for: .milliseconds(500))
```
**Should be:** `CupertinoConstants.Delay.swiftEvolution`

#### SampleCodeDownloader.swift:107, 130, 228, 502
```swift
try await Task.sleep(for: .seconds(1))  // Line 107
try await Task.sleep(for: .seconds(5))  // Line 130
try await Task.sleep(for: .seconds(3))  // Line 228
try await Task.sleep(for: .seconds(2))  // Line 502
```
**Should be:** `CupertinoConstants.Delay.sampleCodeBetweenPages`, `sampleCodePageLoad`, etc.

#### PackageFetcher.swift:190, 192, 291, 293
```swift
try await Task.sleep(for: .seconds(5))    // Line 190
try await Task.sleep(for: .seconds(1.2))  // Line 192
try await Task.sleep(for: .seconds(2))    // Line 291
try await Task.sleep(for: .seconds(0.5))  // Line 293
```
**Should be:** `CupertinoConstants.Delay.packageFetchRateLimit`, etc.

#### Crawler.swift:242
```swift
try await Task.sleep(for: .seconds(30))
```
**Should be:** `CupertinoConstants.Timeout.pageLoadTimeout`

---

### 2. Auto-Save Interval

#### CrawlerState.swift:11
```swift
private var autoSaveInterval: TimeInterval = 30.0 // Save every 30 seconds
```
**Should be:** `CupertinoConstants.Interval.autoSave`

---

### 3. Summary Length

#### SearchIndex.swift:390
```swift
private func extractSummary(from content: String, maxLength: Int = 500) -> String {
```
**Should be:** `CupertinoConstants.Limit.summaryMaxLength`

---

### 4. Rate Limiting Intervals

#### PackageFetcher.swift:189, 290
```swift
if (index + 1) % 50 == 0 {
```
**Should be:** `CupertinoConstants.Interval.progressLogEvery`

#### Crawler.swift:122
```swift
if visited.count % 50 == 0 {
```
**Should be:** `CupertinoConstants.Interval.progressLogEvery`

#### SearchIndexBuilder.swift:154
```swift
if (index + 1) % 50 == 0 {
```
**Should be:** `CupertinoConstants.Interval.progressLogEvery`

---

### 5. HTTP Headers

#### SwiftEvolutionCrawler.swift:82
```swift
request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
```
**Should be:**
```swift
request.setValue(CupertinoConstants.HTTPHeader.githubAccept, forHTTPHeaderField: CupertinoConstants.HTTPHeader.accept)
```

---

### 6. Max Pages Default

#### CupertinoShared.swift:22
```swift
maxPages: 1000
```
**Should be:** `CupertinoConstants.Limit.defaultMaxPages` (which is 15000)
**Note:** This seems like a test value that should be updated!

---

## Constants to Add to Constants.swift

Add these to `CupertinoConstants`:

```swift
// MARK: - Delays and Timeouts

public enum Delay {
    /// Delay between Swift Evolution proposal fetches (milliseconds)
    public static let swiftEvolution: Duration = .milliseconds(500)

    /// Delay between sample code page loads (seconds)
    public static let sampleCodeBetweenPages: Duration = .seconds(1)

    /// Wait time for sample code page to load (seconds)
    public static let sampleCodePageLoad: Duration = .seconds(5)

    /// Delay after sample code interaction (seconds)
    public static let sampleCodeInteraction: Duration = .seconds(3)

    /// Delay before sample code download (seconds)
    public static let sampleCodeDownload: Duration = .seconds(2)

    /// Rate limit delay for package fetching (high priority)
    public static let packageFetchHighPriority: Duration = .seconds(5)

    /// Rate limit delay for package fetching (normal)
    public static let packageFetchNormal: Duration = .seconds(1.2)

    /// Rate limit delay for package star count (high priority)
    public static let packageStarsHighPriority: Duration = .seconds(2)

    /// Rate limit delay for package star count (normal)
    public static let packageStarsNormal: Duration = .seconds(0.5)
}

public enum Timeout {
    /// Timeout for page loading in crawler (seconds)
    public static let pageLoad: Duration = .seconds(30)

    /// Maximum time to wait for WKWebView navigation (seconds)
    public static let webViewNavigation: Duration = .seconds(30)
}

// MARK: - Intervals

public enum Interval {
    /// Auto-save interval for crawler state (seconds)
    public static let autoSave: TimeInterval = 30.0

    /// Log progress every N items
    public static let progressLogEvery: Int = 50
}

// MARK: - Content Limits

public enum ContentLimit {
    /// Maximum length for summary extraction (characters)
    public static let summaryMaxLength: Int = 500

    /// Maximum content preview length (characters)
    public static let previewMaxLength: Int = 200
}
```

---

## Refactoring Plan

### Phase 1: Add New Constants (5 minutes)
1. Add `Delay`, `Timeout`, `Interval`, `ContentLimit` enums to Constants.swift
2. Verify they compile

### Phase 2: Refactor Files (15-20 minutes)

**Files to update:**
1. ✅ SwiftEvolutionCrawler.swift (1 hardcoded value)
2. ✅ SampleCodeDownloader.swift (4 hardcoded values)
3. ✅ PackageFetcher.swift (6 hardcoded values)
4. ✅ Crawler.swift (2 hardcoded values)
5. ✅ CrawlerState.swift (1 hardcoded value)
6. ✅ SearchIndex.swift (1 hardcoded value)
7. ✅ SearchIndexBuilder.swift (1 hardcoded value)
8. ✅ CupertinoShared.swift (1 hardcoded value - fix to use correct default)

**Total:** 8 files, ~17 replacements

### Phase 3: Verify (5 minutes)
1. Run `swift build` to verify compilation
2. Run `swiftlint` to check for any violations
3. Verify constants are used correctly

**Total Time:** ~25-30 minutes

---

## Benefits of Refactoring

1. **Single source of truth** - Change delay/timeout values in one place
2. **Better documentation** - Constants explain why values are what they are
3. **Easier tuning** - Adjust performance without hunting through code
4. **Type safety** - Enums prevent typos and invalid values
5. **Consistency** - All files use same values for same purposes
6. **Testing** - Can override constants for tests

---

## Priority

**Priority:** HIGH (Bug #18 - Magic Number Constants)

This refactoring directly addresses Bug #18 from BUGS.md. After refactoring:
- All magic numbers have names and documentation
- Easy to tune performance parameters
- Clear what each value controls

---

## Next Steps

1. **Get approval** to proceed with refactoring
2. **Add constants** to Constants.swift
3. **Refactor files** one by one
4. **Test** to ensure no breakage
5. **Update BUGS.md** to mark Bug #18 as fixed

---

*End of Constants Refactoring Report*
