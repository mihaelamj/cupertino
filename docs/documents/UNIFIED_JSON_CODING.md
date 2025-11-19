# Unified JSON Coding

**Created:** 2025-11-17
**Purpose:** Centralize JSON encoding/decoding with consistent date strategies

---

## Overview

We've created a unified `JSONCoding` utility in `Sources/CupertinoShared/JSONCoding.swift` to ensure consistent JSON encoding/decoding across the entire codebase, especially for date handling.

## Problem Solved

**Before:** Date encoding/decoding strategies were scattered and inconsistent:
- Some places used ISO8601
- Some places used default (Double timestamps)
- Some places forgot to set any strategy
- Led to "Expected Double but found String" errors

**After:** All code that handles dates uses the unified `JSONCoding` utility:
- Consistent ISO8601 date format everywhere
- Single source of truth for encoding/decoding configuration
- Easy to update date strategy project-wide if needed

---

## API

### Encoders

```swift
// Standard encoder with ISO8601 dates
let encoder = JSONCoding.encoder()

// Pretty-printed encoder with ISO8601 dates
let encoder = JSONCoding.prettyEncoder()
```

### Decoders

```swift
// Standard decoder with ISO8601 dates
let decoder = JSONCoding.decoder()
```

### Convenience Methods

```swift
// Encode to Data
let data = try JSONCoding.encode(myModel)

// Encode pretty-printed to Data
let data = try JSONCoding.encodePretty(myModel)

// Decode from Data
let model = try JSONCoding.decode(MyModel.self, from: data)

// Decode from file
let model = try JSONCoding.decode(MyModel.self, from: fileURL)

// Encode to file (auto-creates directory, pretty-printed)
try JSONCoding.encode(myModel, to: fileURL)
```

---

## Usage in Codebase

### Updated to Use JSONCoding

✅ **CrawlMetadata save/load** (`Sources/CupertinoShared/Models.swift`)
```swift
// Before
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let data = try encoder.encode(self)

// After
try JSONCoding.encode(self, to: url)
```

✅ **Session state checking** (`Sources/CupertinoCLI/Commands.swift`)
```swift
// Before
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let metadata = try decoder.decode(CrawlMetadata.self, from: data)

// After
let metadata = try JSONCoding.decode(CrawlMetadata.self, from: metadataFile)
```

✅ **Test helpers** (`Tests/CupertinoCoreTests/BugTests.swift`)
```swift
// Before
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
return try decoder.decode(CrawlMetadata.self, from: data)

// After
try JSONCoding.decode(CrawlMetadata.self, from: url)
```

### Other JSON Encoding (Doesn't Need ISO8601)

These files use plain `JSONEncoder()` because they don't encode/decode Date fields:

📝 **GitHub API** (`Sources/CupertinoCore/SwiftEvolutionCrawler.swift`)
- Decoding GitHub file listings (no dates)

📝 **Cookie Data** (`Sources/CupertinoCore/SampleCodeDownloader.swift`)
- Browser cookies (no dates)

📝 **Package Lists** (`Sources/CupertinoCore/PackageFetcher.swift`, `PriorityPackageGenerator.swift`)
- Package metadata (no dates, or uses different format)

📝 **MCP Protocol** (`Sources/MCPServer/MCPServer.swift`, `Sources/MCPTransport/Transport.swift`)
- JSON-RPC messages (no dates)

📝 **Configuration** (`Sources/CupertinoShared/Configuration.swift`)
- App configuration (no dates)

---

## Benefits

### 1. Consistency
All date-related JSON operations use ISO8601 format: `"2025-11-17T00:00:00Z"`

### 2. Maintainability
Single place to change date strategy if needed in future

### 3. Less Code
Convenience methods reduce boilerplate:
```swift
// Before: 5 lines
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let data = try encoder.encode(self)
try data.write(to: url)

// After: 1 line
try JSONCoding.encode(self, to: url)
```

### 4. Error Prevention
Impossible to forget date strategy when using `JSONCoding`

---

## Future Improvements

### Potential Additions

1. **Custom date formats:**
```swift
public static func encoder(dateFormat: String) -> JSONEncoder
```

2. **Key encoding strategies:**
```swift
public static func encoder(keyStrategy: JSONEncoder.KeyEncodingStrategy) -> JSONEncoder
```

3. **MCP-specific encoder:**
```swift
// For JSON-RPC (no dates, compact format)
public static func mcpEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    // No date strategy needed, compact format
    return encoder
}
```

### Migration Plan

Could eventually migrate all JSON encoding to use JSONCoding for complete consistency, even when dates aren't involved. This would:
- Make codebase even more consistent
- Make it easier to add global JSON configuration
- Centralize all JSON operations

---

## Testing

All tests pass with unified encoding:

```bash
✅ Bug #1b: outputDirectory saved in session state - PASS
✅ Integration test: Download real Apple doc - PASS
✅ All date encoding/decoding tests - PASS
```

No regressions introduced.

---

## Conclusion

The `JSONCoding` utility successfully:
- ✅ Fixes date encoding/decoding bugs
- ✅ Centralizes JSON configuration
- ✅ Reduces code duplication
- ✅ Prevents future encoding inconsistencies
- ✅ All tests pass

**Status:** Production ready
