# get_inheritance

Walk class-inheritance chains across Apple documentation.

## Synopsis

```json
{
  "name": "get_inheritance",
  "arguments": {
    "symbol": "UIControl",
    "direction": "up",
    "framework": "uikit",
    "depth": 5,
    "format": "json"
  }
}
```

## Description

Resolves the named symbol to its canonical `apple-docs://` URI, then walks the inheritance edges in the requested direction. Returns the ancestors chain (`direction=up`), the descendants tree (`direction=down`), or both (`direction=both`).

## Parameters

### symbol (required)

The symbol's bare name. Resolver strips Apple's HTML site-suffix from stored titles before matching, so `NSObject` resolves the same as `NSObject | Apple Developer Documentation` (see #754 for the suffix-stripping fix).

When the name is ambiguous across frameworks (e.g. `Color` exists in SwiftUI and AppKit), the response is a disambiguation block listing each candidate; re-call with `framework` to pick one.

### direction (optional, default `up`)

- `up`: follow `parentsOf` recursively, e.g. `UIButton -> UIControl -> UIView -> UIResponder -> NSObject`.
- `down`: follow `childrenOf` recursively, e.g. `UIControl -> { UIButton, UISwitch, ... }`.
- `both`: walk both directions at once.

### framework (optional)

Disambiguator when the symbol exists across multiple frameworks.

### depth (optional, default 5)

Maximum hops the walker follows in each direction. The value must be positive; `depth=0` is rejected as an invalid argument.

### format (optional)

Output format. Default: `markdown`; use `json` for a typed GUI-decodable payload.

## Response shape

### Typed JSON

`format=json` returns one machine-readable object for success, empty-tree, ambiguous, and not-found cases. `status` is `ok`, `no_data`, `ambiguous`, or `not_found`. Inheritance tree nodes include both `uri` and display `title`, so clients can render trees without scraping markdown or doing follow-up title lookups.

```json
{
  "symbol": "UIButton",
  "status": "ok",
  "framework": "uikit",
  "uri": "apple-docs://uikit/uibutton",
  "direction": "up",
  "depth": 5,
  "candidates": [
    {
      "uri": "apple-docs://uikit/uibutton",
      "title": "UIButton",
      "framework": "uikit",
      "kind": "class"
    }
  ],
  "ancestors": [
    {
      "uri": "apple-docs://uikit/uicontrol",
      "title": "UIControl",
      "children": []
    }
  ],
  "descendants": []
}
```

### Successful chain (non-empty tree)

```
# Inheritance: UIControl | Apple Developer Documentation

**URI:** `apple-docs://uikit/uicontrol`  **Framework:** `uikit`  **Direction:** `up`  **Depth:** `5`

## Inherits from

- `apple-docs://uikit/uiview`
  - `apple-docs://uikit/uiresponder`
    - `apple-docs://objectivec/nsobject-swift.class`
```

### Empty tree (no edges in the requested direction)

Every empty-tree response carries the `_No inheritance data:` semantic-marker prefix (per #669 contract). The reason after the marker is kind-aware (per #754 secondary fix):

| Resolved symbol kind | Direction | Reason |
|---|---|---|
| `class` | `up` | `Root type: no ancestors above this class in the indexed corpus.` |
| `class` | `down` | `No descendants indexed under this class.` |
| `class` | `both` | `Isolated class: neither ancestors nor descendants indexed in the corpus.` |
| `protocol` | any | `Swift protocol: protocols don't carry inherits-from edges. Try search_conformances for the types that conform to this protocol.` |
| `struct` / `enum` / `actor` | any | `Swift value type (<kind>): value types don't carry inherits-from edges.` |
| nil / unknown | any | Legacy generic fallback (back-compat). |

### Disambiguation (ambiguous name)

```
`Color` is ambiguous across 2 frameworks. Re-call with the matching `framework` argument:

- `Color` in `swiftui` -- apple-docs://swiftui/color
- `Color` in `appkit` -- apple-docs://appkit/nscolor
```

### Symbol not found

```
No symbol named `Foo` in apple-docs. Try `search` first to find the right name, or check `list_frameworks`.
```

## Examples

```bash
# Walk up from UIButton to NSObject
cupertino inheritance UIButton --direction up

# See every UIControl subclass indexed
cupertino inheritance UIControl --direction down

# Both at once
cupertino inheritance UIView --direction both --depth 3
```

## Related

- `search_conformances`: for protocol conformance edges (the inheritance graph doesn't cover those).
- `search_symbols`: for symbol-name pattern search across the AST-extracted symbol index.
- #274: original inheritance-walk implementation.
- #754 (primary): canonical-root resolver fix (Apple-site-suffix stripping).
- #754 (secondary): kind-aware empty-tree response.
- #669: empty-tree semantic-marker contract for AI clients.
