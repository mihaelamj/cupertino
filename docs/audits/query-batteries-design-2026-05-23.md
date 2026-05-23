# Query batteries design (Phase 2-5)

**Filed**: 2026-05-23. **Status**: design, queries-only. **Umbrella**: [#943](https://github.com/mihaelamj/cupertino/issues/943). **Phase issues**: [#944](https://github.com/mihaelamj/cupertino/issues/944), [#945](https://github.com/mihaelamj/cupertino/issues/945), [#946](https://github.com/mihaelamj/cupertino/issues/946), [#947](https://github.com/mihaelamj/cupertino/issues/947).

This document enumerates the query corpora for the four phases extending the Cranfield-paradigm evaluation framework beyond `search` (Phase 1, already shipped at v1.2.0 as `scripts/eval/search-quality-phase1.py`). Each corpus is a list of `(input → documented expected outcome)` fixtures that the future harness consumes. Mirrors the shape of Phase 1's `CANONICAL_QUERIES`.

**Class A** = canonical / strict (one right answer; rank-1 expected). **Class B** = broad / contains-check (must include named element in top-K). **Class C** = negative path (must return documented empty / semantic-marker shape). **Class D** = invariant (count / structural; not result-based).

---

## Phase 2 ([#944](https://github.com/mihaelamj/cupertino/issues/944)): AST tools

5 MCP tools × ~10 queries = 49 fixtures.

### `search_symbols`

| # | Query | Expected (top-K contains) | Class | Notes |
|---|---|---|---|---|
| 1 | `kind=struct, query=View` | `swiftui/view` symbol row | A | apex SwiftUI type |
| 2 | `kind=actor` | any actor symbol with `sourceType=ast` | B | actors are rare in Apple docs |
| 3 | `kind=protocol, query=Delegate` | `*Delegate` protocol from UIKit | B | protocol naming convention |
| 4 | `kind=enum, query=Result` | `swift/result` | A | stdlib type |
| 5 | `kind=class, query=NSObject` | `objectivec/nsobject` | A | root class |
| 6 | `kind=property, query=isActive` | UIScene's `isActive` or similar | B | property symbol |
| 7 | `kind=function, is_async=true` | any async function symbol | B | async filter |
| 8 | `framework=swiftui, kind=struct` | List, Text, Image, etc. | B | framework + kind |
| 9 | `query=Publisher, framework=combine` | `combine/publisher` | A | Combine protocol |
| 10 | `kind=typealias, query=Codable` | `swift/codable` | A | stdlib typealias |

### `search_property_wrappers`

| # | Query | Expected (top-K contains) | Class | Notes |
|---|---|---|---|---|
| 1 | `@State` | SwiftUI `@State` example | A | most common wrapper |
| 2 | `@Binding` | SwiftUI `@Binding` example | A | |
| 3 | `@Observable` | Observation framework `@Observable` | A | new (iOS 17+) |
| 4 | `@MainActor` | any `@MainActor` usage | B | concurrency wrapper |
| 5 | `@Sendable` | any `@Sendable` usage | B | concurrency wrapper |
| 6 | `@Published` | Combine `@Published` | A | |
| 7 | `@AppStorage` | SwiftUI `@AppStorage` | A | |
| 8 | `@EnvironmentObject` | SwiftUI `@EnvironmentObject` | A | |
| 9 | `@StateObject` | SwiftUI `@StateObject` | A | |
| 10 | `@FetchRequest` | CoreData / SwiftData `@FetchRequest` | A | |

### `search_concurrency`

| # | Pattern | Expected (top-K contains) | Class | Notes |
|---|---|---|---|---|
| 1 | `async` | async function symbols | B | broad |
| 2 | `actor` | actor declarations | B | broad |
| 3 | `sendable` | Sendable types / conformances | B | broad |
| 4 | `mainactor` | `@MainActor` symbols | B | broad |
| 5 | `task` | `Task` usage | B | broad |
| 6 | `asyncsequence` | `AsyncSequence` conformances | B | broad |
| 7 | `pattern=async, framework=foundation` | URLSession async APIs | B | filtered |
| 8 | `pattern=actor, framework=foundation` | Foundation actors | B | filtered |

### `search_conformances`

| # | Protocol | Expected (top-K contains) | Class | Notes |
|---|---|---|---|---|
| 1 | `View` | SwiftUI primitive views (Text, Image, List, ...) | B | densest |
| 2 | `Sendable` | broad Sendable types | B | broad |
| 3 | `Codable` | Codable types across Foundation | B | broad |
| 4 | `Identifiable` | Identifiable types | B | broad |
| 5 | `ObservableObject` | Combine ObservableObject | B | Combine integration |
| 6 | `AsyncSequence` | AsyncSequence conformers | B | concurrency |
| 7 | `Equatable` | Equatable types | B | broad |
| 8 | `Hashable` | Hashable types | B | broad |
| 9 | `Error` | Error conformers (URLError, DecodingError, ...) | B | broad |
| 10 | `RandomAccessCollection` | Array, ArraySlice, etc. | B | stdlib |

### `search_generics`

| # | Constraint | Expected (top-K contains) | Class | Notes |
|---|---|---|---|---|
| 1 | `Sendable` | generic types/funcs with `where T: Sendable` | B | broad |
| 2 | `Hashable` | generic types with `where T: Hashable` | B | broad |
| 3 | `View` | SwiftUI `where Content: View` generics | B | SwiftUI |
| 4 | `BinaryInteger` | numeric generics | B | stdlib |
| 5 | `Collection` | Collection-constrained generics | B | broad |
| 6 | `Comparable` | Comparable-constrained generics | B | broad |
| 7 | `Codable` | Codable-constrained generics | B | broad |
| 8 | `Identifiable` | Identifiable-constrained generics | B | broad |
| 9 | `constraint=Sendable, framework=swiftui` | SwiftUI Sendable generics | B | filtered |
| 10 | `constraint=View, framework=swiftui` | SwiftUI View generics (high density) | B | filtered |

---

## Phase 3 ([#945](https://github.com/mihaelamj/cupertino/issues/945)): `get_inheritance`

20 walks + 10 negative-path probes = 30 fixtures.

### Up walks (ancestors)

| # | Symbol | Expected path | Class | Notes |
|---|---|---|---|---|
| 1 | `UIView` | UIView → UIResponder → NSObject | A | UIKit canonical |
| 2 | `UIButton` | UIButton → UIControl → UIView → UIResponder → NSObject | A | UIKit deep chain |
| 3 | `UIScrollView` | UIScrollView → UIView → UIResponder → NSObject | A | |
| 4 | `UITableView` | UITableView → UIScrollView → UIView → UIResponder → NSObject | A | |
| 5 | `UIViewController` | UIViewController → UIResponder → NSObject | A | |
| 6 | `NSView` | NSView → NSResponder → NSObject | A | AppKit canonical |
| 7 | `NSWindow` | NSWindow → NSResponder → NSObject | A | |
| 8 | `NSImageView` | NSImageView → NSControl → NSView → NSResponder → NSObject | A | |
| 9 | `NSDocument` | NSDocument → NSObject | A | |
| 10 | `NSPersistentContainer` | NSPersistentContainer → NSObject | A | Foundation |

### Down walks (descendants)

| # | Symbol | Expected (top-K descendants) | Class | Notes |
|---|---|---|---|---|
| 11 | `UIControl` | UIButton, UISlider, UISwitch, UIDatePicker, ... | B | UIControl tree |
| 12 | `UIView` (down) | UILabel, UIImageView, UIButton, UIScrollView, ... | B | UIView tree (large) |
| 13 | `UIScrollView` (down) | UITableView, UICollectionView, UITextView | B | |
| 14 | `NSControl` (down) | NSButton, NSSlider, NSStepper, NSTextField, ... | B | NSControl tree |
| 15 | `NSObject` (down, depth=1) | UIResponder, NSResponder, NSObject children | B | densest possible |

### Both walks

| # | Symbol | Expected | Class | Notes |
|---|---|---|---|---|
| 16 | `UIControl` (direction=both) | up: UIView/UIResponder/NSObject; down: UIButton, UISlider, ... | B | bidirectional |
| 17 | `NSView` (direction=both) | up: NSResponder/NSObject; down: NSControl, NSTextView, ... | B | bidirectional |

### Depth bounds

| # | Symbol | Depth | Expected | Class | Notes |
|---|---|---|---|---|---|
| 18 | `UIButton` | depth=1 | UIControl only | A | depth boundary |
| 19 | `UIButton` | depth=2 | UIControl, UIView | A | |
| 20 | `UIButton` | depth=10 | full chain to NSObject (no over-walk) | A | depth saturation |

### Negative-path probes (must surface semantic markers)

| # | Symbol | Expected marker | Class | Notes |
|---|---|---|---|---|
| 21 | `View` (SwiftUI protocol) | "_No inheritance data" + redirect to `search_conformances` | C | protocol probe |
| 22 | `Codable` | redirect to `search_conformances` | C | protocol probe |
| 23 | `Int` | "_No inheritance data" + "Swift value type" | C | value-type probe |
| 24 | `String` | "_No inheritance data" + "Swift value type" | C | value-type probe |
| 25 | `Array` (struct) | "_No inheritance data" + "Swift value type" | C | value-type probe |
| 26 | `Result` (enum) | "_No inheritance data" + "Swift value type" | C | enum value type |
| 27 | `Foo` (no such symbol) | "_No inheritance data" + "not found" | C | absent symbol |
| 28 | `NSObject` (up direction) | "_No inheritance data" + "Root type" | C | root class |
| 29 | `MainActor` (global actor) | "_No inheritance data" + "Swift value type" or actor semantic | C | actor probe (boundary case) |
| 30 | empty symbol | usage error | C | input validation |

---

## Phase 4 ([#946](https://github.com/mihaelamj/cupertino/issues/946)): read commands

20 fixtures across 3 commands.

### `read_document` URIs (one per source × 2 formats = 16 fixtures)

| # | URI | Format | Expected | Class | Notes |
|---|---|---|---|---|---|
| 1 | `apple-docs://swiftui/view` | json | non-empty `structuredContent` | A | apple-docs json |
| 2 | `apple-docs://swiftui/view` | markdown | non-empty markdown body | A | apple-docs markdown |
| 3 | `samples://...` (pick a known one) | json | non-empty | A | samples-side doc |
| 4 | `samples://...` | markdown | non-empty | A | |
| 5 | `hig://...` (pick one) | json | non-empty | A | HIG |
| 6 | `hig://...` | markdown | non-empty | A | |
| 7 | `apple-archive://...` (Core Animation Guide) | json | non-empty | A | archive |
| 8 | `apple-archive://...` | markdown | non-empty | A | |
| 9 | `swift-evolution://se-0376` (StaticBigInt) | json | non-empty | A | SE proposal |
| 10 | `swift-evolution://se-0376` | markdown | non-empty | A | |
| 11 | `swift-org://documentation/...` | json | non-empty | A | swift.org |
| 12 | `swift-org://...` | markdown | non-empty | A | |
| 13 | `swift-book://documentation/the-swift-programming-language/...` | json | non-empty | A | swift book |
| 14 | `swift-book://...` | markdown | non-empty | A | |
| 15 | `packages://...` (Alamofire/Alamofire) | json | non-empty | A | packages |
| 16 | `packages://...` | markdown | non-empty | A | |

### `read_sample` (project_id × 2 = 2 fixtures)

| # | project_id | Expected | Class | Notes |
|---|---|---|---|---|
| 17 | `appintents-make-your-app-s-content-available-in-spotlight` | non-empty README + file count | A | known sample |
| 18 | `fictional-nonexistent-project` | not-found error | C | negative probe |

### `read_sample_file` (project_id × file_path = 2 fixtures)

| # | project_id, file_path | Expected | Class | Notes |
|---|---|---|---|---|
| 19 | `(known-project, ContentView.swift)` | non-empty source | A | swift source |
| 20 | `(known-project, nonexistent/file.swift)` | not-found error | C | negative |

---

## Phase 5 ([#947](https://github.com/mihaelamj/cupertino/issues/947)): list / doctor / package-search

15 fixtures.

### `list_frameworks` (1 fixture, invariant)

| # | Invocation | Expected | Class | Notes |
|---|---|---|---|---|
| 1 | no params | rows = 428 (v1.2.x bundle) ± allowed drift; must contain {swiftui, foundation, uikit, appkit, combine, swiftdata} | D | structural |

### `list_samples` (1 fixture, invariant)

| # | Invocation | Expected | Class | Notes |
|---|---|---|---|---|
| 2 | no params | projects = 619 (v1.2.x bundle); must contain known projects | D | structural |

### `doctor` (4 fixtures, structural)

| # | Invocation | Expected | Class | Notes |
|---|---|---|---|---|
| 3 | `doctor` | exit 0, "✅ All checks passed" footer | D | happy path |
| 4 | `doctor --kind-coverage` | exit 0, per-source kind histogram | D | kind audit |
| 5 | `doctor --freshness` | exit 0, per-source p50/p90/newest table | D | freshness audit |
| 6 | `doctor --save` | exit 0 + extra `cupertino save` preflight section | D | maintainer view |

### `package-search` (9 fixtures)

| # | Query | Expected | Class | Notes |
|---|---|---|---|---|
| 7 | `alamofire` | rank-1 = `Alamofire/Alamofire` | A | famous name |
| 8 | `swift-collections` | rank-1 = `apple/swift-collections` | A | Apple SPM package |
| 9 | `swift-algorithms` | rank-1 = `apple/swift-algorithms` | A | Apple SPM package |
| 10 | `kingfisher` | rank-1 = `onevcat/Kingfisher` | A | famous name |
| 11 | `json` | top 5 contains some JSON-related package | B | broad |
| 12 | `networking` | top 5 contains networking package | B | semantic |
| 13 | `apple_imports=SwiftUI` | results all import SwiftUI | B | filter |
| 14 | `apple_imports=Combine` | results all import Combine | B | filter |
| 15 | empty query | usage error | C | input validation |

---

## Notes on baseline curation

When the harnesses for each phase land, the FIRST run becomes the baseline. Subsequent runs compare against that baseline via paired McNemar + Wilcoxon (mirror of Phase 1). The "expected (top-K contains)" column in the tables above is the FIXTURE: the documented right answer. The harness produces JSON with per-query rank + per-query pass/fail against the fixture.

Class D (invariant) probes don't produce ranks; they produce structural pass/fail (e.g., "row count == 428 ± 5").

Negative-path probes (Class C) require the harness to assert ON the absence of results OR on the presence of a documented semantic marker (e.g., `_No inheritance data`).

Total query count across Phase 2-5: **49 + 30 + 20 + 15 = 114 fixtures.** Plus Phase 1's 50 = 164 fixtures total once the four phases ship.
