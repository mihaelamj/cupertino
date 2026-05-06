---
name: cupertino
description: This skill should be used when working with Apple APIs, iOS/macOS/visionOS development, or Swift language questions. Covers searching Apple developer documentation, looking up SwiftUI views, finding UIKit APIs, reading Apple docs, browsing Swift Evolution proposals, checking Human Interface Guidelines, and exploring Apple sample code. Supports 300+ frameworks including SwiftUI, UIKit, Foundation, and Combine via offline search of 405,000+ documentation pages.
allowed-tools: Bash(cupertino *)
---

# Cupertino: Apple Documentation Search

Search 405,000+ Apple developer documentation pages offline. Cupertino is a lexical search engine over Apple's docs, samples, HIG, Swift Evolution, Swift.org, the Swift book, and Swift package metadata. It returns deterministic, citable results, never hallucinations.

**Your job (the LLM) is to translate the user's question into the right cupertino query, cite results in your answer, and verify everything you say traces back to a real Apple doc.**

## Setup

First-time setup (downloads ~2.4GB database):
```bash
cupertino setup
```

If `cupertino setup` hasn't been run, do that first.

## Search strategy

Cupertino does exact lexical matching. **You handle the language understanding before calling it.**

### 1. Translate to canonical Apple terms before searching

Users describe things by appearance, by UIKit muscle memory, or with typos. Cupertino indexes Apple's canonical names. Translate first; search second.

**Common translations:**

| User says | Likely SwiftUI | Likely UIKit | Likely AppKit |
|---|---|---|---|
| search bar / searchbar | `searchable` modifier | `UISearchBar` | `NSSearchField` |
| text field | `TextField` | `UITextField` | `NSTextField` |
| list view / table view | `List` | `UITableView` / `UICollectionView` | `NSTableView` |
| segmented control | `Picker(.segmented)` | `UISegmentedControl` | `NSSegmentedControl` |
| spinner / loading indicator | `ProgressView` | `UIActivityIndicatorView` | `NSProgressIndicator` |
| alert | `.alert` modifier | `UIAlertController` | `NSAlert` |
| modal / popup | `.sheet`, `.fullScreenCover` | `present(_:animated:)` | `NSWindow.beginSheet` |
| switch / toggle | `Toggle` | `UISwitch` | `NSSwitch` |
| stepper | `Stepper` | `UIStepper` | `NSStepper` |
| web view | `WKWebView` (UIKit) | `WKWebView` | `WKWebView` |

When you translate, **tell the user**: "Searching for `searchable` (SwiftUI equivalent of search bar)."

### 2. Handle typos and "did you mean" yourself

Cupertino does not fuzzy-match. If the user types `searchabe`, calling `cupertino search "searchabe"` will return weak results. **You** correct the typo first, then search:

- `searchabe` → search for `searchable`
- `unviewcontroller` → search for `UIViewController`
- `tabel view` → search for `UITableView` or `List` (depending on framework)

Use your knowledge of Apple naming conventions. If unsure, search for both the literal query and your guess; compare results.

### 3. Infer the framework from context

Use `--framework` to narrow when the framework is obvious:

- Conversation about SwiftUI views → `--framework swiftui`
- Symbol prefix `NS*` → `--framework appkit`
- Symbol prefix `UI*` → `--framework uikit`
- Symbol prefix `MK*` → `--framework mapkit`
- File the user is editing imports a specific framework → use that

If the framework is genuinely ambiguous, search without `--framework` and disambiguate from results.

### 4. Prefer current API over deprecated

Apple keeps deprecated symbols indexed. Lead with the current canonical:

- `UIWebView` is deprecated → recommend `WKWebView`
- `UISearchDisplayController` is deprecated → recommend `UISearchController`
- `UITableView` for new code → recommend `UICollectionView` or SwiftUI `List`

When you mention a deprecated symbol in your answer, flag it.

### 5. Recovery when results are weak

If a search returns nothing useful:

1. **Try a paradigm bridge**: if a UIKit name returned nothing in a SwiftUI context, search the SwiftUI canonical (and vice versa).
2. **Try conceptual phrasing**: if `tableview` returns weak results, try `cupertino search "building list interfaces"` or `cupertino search "displaying a list of items" --source apple-docs` to find Apple's conceptual pages.
3. **Try samples**: descriptive queries often hit better in the samples corpus. `cupertino search "search interface" --source samples`.
4. **Always tell the user what you tried**: "No direct hit for `searchbar`. Retried as `searchable` (SwiftUI), found 12 results."

Never silently rewrite without telling the user what you did.

### 6. Migration / cross-paradigm queries

If the user asks "SwiftUI equivalent of UITableView" or mentions migration:

1. Search both frameworks
2. Look for migration-guide pages (often titled "Migrating from X to Y")
3. Present both: the new canonical (e.g., `List`) AND the old symbol the user knows (`UITableView`)

## Citation and verification (do this for every answer)

Cupertino's value is grounding. **Use it.**

### Cite as you go

For every API, framework, or concept you mention in your answer, name the cupertino URI it came from. Example:

> Use `searchable(text:)` ([apple-docs://swiftui/view/searchable(text:)](apple-docs://swiftui/view/searchable(text:))) to add a search field to a SwiftUI view. The modifier was introduced in iOS 15.

This costs you almost nothing in tokens (you're already typing the symbol name) and prevents hallucination because you can only cite what you actually retrieved.

### Verify before sending

Before finalizing your answer, scan it for every API/symbol you named. Each one must trace back to a URI you got from cupertino. If it doesn't:

1. **Re-search to confirm it exists**: `cupertino search "<symbol>" --format json`
2. **If still no hit**, mark it as uncertain in your answer ("I'm less sure about X; couldn't confirm in Apple docs") or remove it
3. **Never fabricate** parameter names, return types, or platform availability

### Token-efficient verification

| Pattern | Cost | When to use |
|---|---|---|
| Cite as you go (no extra calls) | ~5% overhead | Always |
| Re-search uncertain claims | 1 search call per claim (~500 tokens) | When you mention an API you don't 100% remember |
| Full LLM verify pass | 1.5–2× baseline | High-stakes answers (production code, security) |
| Wrong answer + user correction | 3–5× baseline | Worst case; avoid |

The cite-as-you-go default is essentially free and prevents most hallucinations. Re-search for uncertain claims is cheap. Full verify passes are usually overkill.

## Commands

### Search Documentation
Search across all sources (apple-docs, samples, hig, swift-evolution, swift-org, swift-book, packages):
```bash
cupertino search "SwiftUI View" --format json
cupertino search "SwiftUI View" --format json --limit 5
```

Filter by source:
```bash
cupertino search "async await" --source swift-evolution --format json
cupertino search "NavigationStack" --source apple-docs --format json
cupertino search "button styles" --source samples --format json
cupertino search "button guidelines" --source hig --format json
```

Filter by framework:
```bash
cupertino search "@Observable" --framework swiftui --format json
```

### Read a Document
Retrieve full document content by URI:
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format json
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown
```

### List Frameworks
List all indexed frameworks with document counts:
```bash
cupertino list-frameworks --format json
```

### List Sample Projects
Browse indexed Apple sample code projects:
```bash
cupertino list-samples --format json
cupertino list-samples --framework swiftui --format json
```

### Read Sample Code
Read a sample project or specific file:
```bash
cupertino read-sample "foodtrucksampleapp" --format json
cupertino read-sample-file "foodtrucksampleapp" "FoodTruckApp.swift" --format json
```

## Sources

| Source | Description |
|--------|-------------|
| `apple-docs` | Official Apple documentation (301,000+ pages) |
| `swift-evolution` | Swift Evolution proposals |
| `hig` | Human Interface Guidelines |
| `samples` | Apple sample code projects |
| `swift-org` | Swift.org documentation |
| `swift-book` | The Swift Programming Language book |
| `apple-archive` | Legacy guides (Core Animation, Quartz 2D, KVO/KVC) |
| `packages` | Swift package documentation |

## Output Formats

All commands support `--format` with these options:
- `text` - Human-readable output (default for most commands)
- `json` - Structured JSON for parsing (use this when reasoning about results)
- `markdown` - Formatted markdown

## Example JSON Output

```json
{
  "results": [
    {
      "uri": "apple-docs://swiftui/documentation_swiftui_vstack",
      "title": "VStack",
      "framework": "SwiftUI",
      "summary": "A view that arranges its children vertically",
      "source": "apple-docs"
    }
  ],
  "count": 1,
  "query": "VStack"
}
```

## Tips

- Use `--source` to narrow searches to a specific documentation source
- Use `--framework` to filter by framework (e.g., swiftui, foundation, uikit)
- Use `--limit` to control the number of results returned (default works well; 5–10 is plenty)
- URIs from search results can be used directly with `cupertino read`
- Legacy archive guides are excluded from search by default; add `--include-archive` to include them
- Code examples in the indexed docs are usually more useful than descriptions for understanding API usage
