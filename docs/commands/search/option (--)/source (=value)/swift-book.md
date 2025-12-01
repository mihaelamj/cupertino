# swift-book

The Swift Programming Language book source

## Synopsis

```bash
cupertino search <query> --source swift-book
```

## Description

Filters search results to only include content from "The Swift Programming Language" book. This is the official guide to Swift, covering language fundamentals and advanced features.

## Content

- **Language Guide** chapters
- **Language Reference** sections
- **Code examples** and explanations
- **Best practices**

## Topics Covered

- Basics (constants, variables, types)
- Control flow
- Functions and closures
- Classes, structs, enums
- Protocols and extensions
- Generics
- Concurrency
- Memory safety
- Macros

## Typical Size

- **~100 pages** indexed
- **~20 MB** on disk

## Examples

### Search for Closures
```bash
cupertino search "closures" --source swift-book
```

### Search for Generics
```bash
cupertino search "generics" --source swift-book
```

### Search for Concurrency
```bash
cupertino search "async" --source swift-book
```

## URI Format

Results use the `swift-book://` URI scheme:

```
swift-book://{chapter_path}
```

## How to Populate

```bash
# Fetch Swift book (part of swift type)
cupertino fetch --type swift

# Build index
cupertino save
```

## Notes

- Part of swift.org content
- Excellent for learning Swift fundamentals
- Framework field is typically `nil`
- Updated with each Swift release
