# <query>

Search query string (required)

## Synopsis

```bash
cupertino search <query>
```

## Description

The search term to find in the documentation index. This is a **required positional argument**.

## Examples

### Single Word
```bash
cupertino search View
```

### Multiple Words (Quoted)
```bash
cupertino search "async await"
```

### Framework Name
```bash
cupertino search SwiftUI
```

### API Symbol
```bash
cupertino search URLSession
```

## Search Behavior

- Full-text search across all indexed documentation
- Matches title, content, and metadata
- Results ranked by relevance score
- Case-insensitive matching

## Notes

- Required argument - cannot be omitted
- Quote multi-word queries
- Supports partial matches
