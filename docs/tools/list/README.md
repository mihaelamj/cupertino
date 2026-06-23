# list

Navigate a source's documentation hierarchy by level. One source-aware entry point for the whole
browse tree, driven by each source's self-described `Source.Hierarchy`.

## Synopsis

```json
{
  "name": "list",
  "arguments": {
    "source": "apple-docs",
    "level": 2,
    "parent": "swiftui",
    "offset": 0,
    "limit": 100
  }
}
```

## Description

`list` replaces the source-blind, fixed-shape browsing that `list_frameworks` / `list_documents` /
`list_children` assumed (framework then document). Sources differ: apple-docs is
framework then page then topic group (3 levels), while swift-evolution is a flat list of
proposals (1 level). `list` asks the source for its shape, then walks it.

- `list(source)` (or `level` omitted / `0`) returns the source's hierarchy descriptor: its depth,
  the kind of node at each level, which level is the leaf, and the leaf content type.
- `list(source, level: 1)` lists the top level (the source's own frameworks / proposals / ...).
- `list(source, level: N, parent: <id|uri>)` lists level `N` under a parent from the level above
  (a framework id at level 2, a node uri at level 3).
- Leaf nodes are read with [`read_document`](../read_document/).

The aliases below are kept for existing clients:

| Alias | Equivalent |
|-------|------------|
| [`list_frameworks`](../list_frameworks/) | `list(source, level: 1)` |
| [`list_documents`](../list_documents/) | `list(source, level: 2, parent: <framework>)` |
| [`list_children`](../list_children/) | `list(source, level: 3, parent: <uri>)` |

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `source` | Yes | Source to browse (for example `apple-docs`, `apple-archive`, `swift-evolution`) |
| `level` | No | 1-based level to enumerate. Omit (or `0`) to describe the source. |
| `parent` | For level ≥ 2 | Parent node from the level above: a framework id at level 2, a node uri at level 3 |
| `offset` | No | Zero-based offset for paged levels. Default: `0` |
| `limit` | No | Maximum items to return. Default: `100`, maximum: `500` |

## Response

### Level 0 (describe)

```json
{
  "source": "apple-docs",
  "kind": "describe",
  "depth": 3,
  "leafContentType": "markdown",
  "levels": [
    { "level": 1, "kind": "framework", "isLeaf": false },
    { "level": 2, "kind": "page", "isLeaf": false },
    { "level": 3, "kind": "topic", "isLeaf": true }
  ]
}
```

`leafContentType` is one of `markdown`, `image`, `pdf`, `code`.

### Level N (navigate)

```json
{
  "source": "apple-archive",
  "level": 1,
  "levelKind": "framework",
  "isLeafLevel": false,
  "parent": null,
  "offset": 0,
  "limit": 100,
  "total": 14,
  "items": [
    { "id": "Foundation", "title": "Foundation", "kind": "framework", "hasChildren": true, "count": 170 }
  ]
}
```

`count` is the document count for level-1 framework rows; it is omitted at deeper levels.
`hasChildren` tells a client whether it can descend another level.

## Examples

Describe a source, then walk it:

```json
{ "name": "list", "arguments": { "source": "swift-evolution" } }
```

```json
{ "name": "list", "arguments": { "source": "apple-archive", "level": 1 } }
```

```json
{ "name": "list", "arguments": { "source": "apple-archive", "level": 2, "parent": "Foundation" } }
```

## See Also

- [read_document](../read_document/) - Read a leaf document by URI
- [list_frameworks](../list_frameworks/) / [list_documents](../list_documents/) / [list_children](../list_children/) - Compatibility aliases
- [search](../search/) - Search documentation by keywords
