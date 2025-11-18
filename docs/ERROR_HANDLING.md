# Error Handling & Functional Patterns

**Version:** 1.0
**Last Updated:** 2025-11-18
**Swift Version:** 6.2
**Language Mode:** Swift 6 with Strict Concurrency Checking

---

## Table of Contents

1. [Overview](#overview)
2. [Modern Swift Error Handling](#modern-swift-error-handling)
3. [Functional Programming Patterns](#functional-programming-patterns)
4. [Implementation Guidelines](#implementation-guidelines)
5. [Naming Conventions](#naming-conventions)
6. [Summary](#summary)

---

## Overview

This document defines the error handling and functional programming patterns used in Cupertino. The goal is to maintain clean, idiomatic Swift 6 code while incorporating practical functional programming concepts where they provide clear value.

### Philosophy

- **Pragmatic over theoretical** - Use patterns that solve real problems
- **Swift-first** - Prefer Swift stdlib and language features over custom abstractions
- **Modern async/await** - Leverage Swift 6 concurrency for error handling
- **Minimal abstractions** - Only introduce patterns that reduce boilerplate or improve safety

---

## Modern Swift Error Handling

### 1. Use `async throws` for Most Code (Priority: HIGH)

**Purpose**: Clean, idiomatic error handling for async/await

**Use cases**: 95% of our code
- Sequential operations
- Single async calls
- Normal error flows
- Any code that can propagate errors synchronously

**Why**: Apple's recommended pattern for Swift 6 concurrency

**Example**:
```swift
func fetchPackageMetadata(url: URL) async throws -> PackageMetadata {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw PackageFetchError.invalidResponse
    }
    return try JSONDecoder().decode(PackageMetadata.self, from: data)
}
```

**Current usage**: Already using throughout codebase ✅

**Effects on other code**:
- Callers must use `await` and handle errors with `try`
- Errors propagate up the call stack automatically
- Cannot be called from synchronous contexts
- Works seamlessly with Swift 6 actors and concurrency

---

### 2. Built-in Result Type - ONLY for Specific Cases (Priority: LOW)

**IMPORTANT**: Use Swift stdlib `Result<Success, Failure>` - don't create custom implementation

**Apple's guidance**: "Use when you can't return errors synchronously"

**Actual use case in Cupertino**: `TaskGroup.nextResult()` for parallel error collection

**When to use**:
- Collecting errors from parallel operations with `TaskGroup`
- Serialization/memoization of throwing operations
- Converting between throwing and non-throwing APIs

**When NOT to use**:
- Sequential operations → use `async throws`
- Normal async/await code → use `async throws`
- Callback-based APIs → use async/await instead

**Example from codebase** (Commands.swift:84):
```swift
await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { try await self.crawlDocs() }
    group.addTask { try await self.crawlSwift() }
    group.addTask { try await self.crawlEvolution() }

    // Collect errors from parallel tasks
    for await result in group {
        switch result {
        case .success:
            continue
        case .failure(let error):
            print("Crawl failed: \(error)")
        }
    }
}
```

**Mathematical basis**: Functor/Monad (supports `map`, `flatMap`, `mapError`)

**Current usage**: Already using correctly in Commands.swift:84 for `--type all` parallel crawls ✅

---

## Functional Programming Patterns

### 3. Semigroup Protocol (Priority: MEDIUM)

**Purpose**: Combine statistics from multiple operations

**Mathematical basis**: Abstract algebra - associative binary operation

**Definition**:
```swift
/// A type that can combine two values into one via an associative binary operation.
///
/// Mathematically: ∀ a,b,c ∈ S: (a ⊕ b) ⊕ c = a ⊕ (b ⊕ c)
protocol Semigroup {
    /// Combines two values associatively
    static func combine(_ lhs: Self, _ rhs: Self) -> Self
}
```

**Use cases**:
- Merging `CrawlStatistics` from multiple crawls
- Combining `PackageFetchStatistics` from parallel fetches
- Aggregating results from `TaskGroup` operations

**Example implementation**:
```swift
extension CrawlStatistics: Semigroup {
    static func combine(_ lhs: CrawlStatistics, _ rhs: CrawlStatistics) -> CrawlStatistics {
        CrawlStatistics(
            totalPagesVisited: lhs.totalPagesVisited + rhs.totalPagesVisited,
            totalPagesSaved: lhs.totalPagesSaved + rhs.totalPagesSaved,
            totalPagesSkipped: lhs.totalPagesSkipped + rhs.totalPagesSkipped,
            errors: lhs.errors + rhs.errors,
            duration: max(lhs.duration, rhs.duration),
            lastCrawled: max(lhs.lastCrawled, rhs.lastCrawled)
        )
    }
}

// Usage
let totalStats = statistics.reduce(into: CrawlStatistics.empty) {
    $0 = CrawlStatistics.combine($0, $1)
}
```

**Benefit**: Clean, composable statistics merging with mathematical guarantees

---

### 4. Sum Types - Enums with Associated Values (Already Using ✅)

**Purpose**: Model mutually exclusive states and detailed error cases

**Mathematical basis**: Tagged union, coproduct in category theory

**Current usage**: 13 error enums in codebase
- `SearchError`
- `PackageFetchError`
- `CrawlerError`
- `SampleCodeError`
- And 9 more...

**Example**:
```swift
public enum SearchError: Error, Sendable, CustomStringConvertible {
    case databaseNotFound(String)
    case databaseCorrupted(String)
    case queryFailed(String)
    case invalidQuery(String)

    public var description: String {
        switch self {
        case .databaseNotFound(let path):
            return "Search database not found at: \(path)"
        case .databaseCorrupted(let reason):
            return "Search database corrupted: \(reason)"
        case .queryFailed(let reason):
            return "Search query failed: \(reason)"
        case .invalidQuery(let query):
            return "Invalid search query: \(query)"
        }
    }
}
```

**Action**: Continue current excellent pattern ✅

**Effects on other code**:
- Exhaustive pattern matching enforced by compiler
- Type-safe error information with associated values
- Clear documentation of all possible error cases
- Works seamlessly with `throw` and `catch`

---

### 5. Product Types - Immutable Structs (Already Using ✅)

**Purpose**: Model data with multiple fields

**Mathematical basis**: Cartesian product

**Current usage**: All models use immutable `struct` with `let`, `Sendable`, `Codable`

**Example**:
```swift
public struct PackageMetadata: Sendable, Codable {
    let name: String
    let url: URL
    let description: String?
    let stars: Int
    let lastUpdated: Date
    let topics: [String]
}
```

**Action**: Continue current excellent pattern ✅

**Effects on other code**:
- Thread-safe due to immutability
- `Sendable` conformance allows safe sharing across actors
- Value semantics prevent unintended mutations
- Compiler-generated memberwise initializers

---

### 6. Functors & Monads - map/flatMap (Already Using ✅)

**Purpose**: Transform and chain operations on wrapped values

**Mathematical basis**: Category theory - endofunctors and monad bind operation

**Current usage**: Swift stdlib implementations
- `Array.map`, `Array.flatMap`
- `Optional.map`, `Optional.flatMap`
- `Result.map`, `Result.flatMap`
- `AsyncSequence.map`, `AsyncSequence.flatMap`

**Example**:
```swift
// Functor: map transforms wrapped values
let urls = packages.map { $0.url }

// Monad: flatMap chains operations
let metadata = try await urls.compactMap { url in
    try? await fetchPackageMetadata(url: url)
}

// Result monad
let result: Result<Package, Error> = fetchResult
    .map { $0.name }
    .flatMap { name in validateName(name) }
```

**Action**: Already using stdlib implementations ✅

**Effects on other code**:
- Composable transformations
- Type inference handles complex generic types
- Works with Swift's value semantics
- No custom abstractions needed

---

## Optional Patterns (Low Priority)

### 7. Monoid Protocol (If Implementing Semigroup)

**Purpose**: Identity element for safe reduction

**Mathematical basis**: Abstract algebra - semigroup with identity element

**Definition**:
```swift
/// A semigroup with an identity element.
///
/// Mathematically: ∃ e ∈ S: ∀ a ∈ S: e ⊕ a = a ⊕ e = a
protocol Monoid: Semigroup {
    /// The identity element
    static var empty: Self { get }
}
```

**Example**:
```swift
extension CrawlStatistics: Monoid {
    static var empty: CrawlStatistics {
        CrawlStatistics(
            totalPagesVisited: 0,
            totalPagesSaved: 0,
            totalPagesSkipped: 0,
            errors: [],
            duration: 0,
            lastCrawled: Date.distantPast
        )
    }
}

// Usage - safe reduction without initial value
let totalStats = statistics.reduce(CrawlStatistics.empty, CrawlStatistics.combine)
```

**When to implement**: If Semigroup reduces boilerplate and you need safe reduction

---

### 8. Optional Extensions (If Reduces Boilerplate)

**Purpose**: Convert Optional to throwing code

**Mathematical basis**: Monad transformation

**Example**:
```swift
extension Optional {
    /// Unwraps the optional or throws an error
    func orThrow(_ error: Error) throws -> Wrapped {
        guard let value = self else {
            throw error
        }
        return value
    }
}

// Usage
let package = try packageCache[name].orThrow(PackageFetchError.notFound(name))
```

**When to implement**: If pattern appears frequently and reduces boilerplate

---

## Patterns to Skip (Not Applicable)

### ❌ Heavy Category Theory
**Why skip**: Too academic for CLI tool
**What to keep**: Basic concepts (functors, monads) with Swift naming

### ❌ IO Monad
**Why skip**: Swift's actors + async/await provide better solution
**Use instead**: Swift 6 concurrency primitives

### ❌ Applicative Functors
**Why skip**: Current "fail fast" validation is simpler
**Use instead**: Sequential validation with `async throws`

### ❌ Custom Result Type
**Why skip**: Swift stdlib already provides it
**Use instead**: `Result<Success, Failure>` from Swift stdlib

---

## Naming Conventions

### ✅ Use (Swift stdlib names):

| Name | Purpose | Mathematical Term |
|------|---------|-------------------|
| `map` | Transform wrapped values | Functor |
| `flatMap` | Chain operations | Monad bind / Kleisli composition |
| `filter` | Select elements | Predicate filtering |
| `reduce` | Fold/collapse to single value | Catamorphism |
| `compactMap` | Map and remove nils | Functor + filter |

### ❌ Avoid (too Haskell-y):

Don't use: `fmap`, `bind`, `pure`, `return`, `traverse`, `sequence`, `foldMap`

**Reason**: Swift has established conventions. Use Swift naming for better integration with ecosystem and IDE support.

---

## Implementation Guidelines

### Priority Order

1. **HIGH**: Use `async throws` for 95% of code
2. **MEDIUM**: Implement Semigroup for statistics if it reduces boilerplate
3. **LOW**: Use Result only for TaskGroup error collection
4. **OPTIONAL**: Add Monoid/Optional extensions if patterns emerge

### Decision Tree

```
Need error handling?
├─ Sequential operation? → Use `async throws`
├─ Parallel operations?
│  ├─ Need all results? → Use TaskGroup + Result
│  └─ Fail on first error? → Use `async throws`
└─ Synchronous callback API? → Convert to async/await

Need to combine statistics?
├─ Simple addition? → Just use `+` operator
└─ Complex merging? → Consider Semigroup protocol

Need to transform collections?
└─ Use Swift stdlib: map, flatMap, filter, reduce, compactMap
```

---

## Summary

### Primary Approach
**Use `async throws` for 95% of code** - This is Apple's modern Swift 6 pattern for error handling.

### Result Type
**Only use Swift stdlib `Result` for `TaskGroup.nextResult()`** - For parallel error collection, not sequential code.

### FP Patterns
**Focus on practical patterns we're already using**:
- Sum types (enums with associated values)
- Product types (immutable structs)
- map/flatMap from Swift stdlib

### New Patterns
**Add Semigroup for statistics merging** - Only if it reduces boilerplate compared to custom merging functions.

### Avoid
- Heavy category theory abstractions
- Custom Result implementations
- Haskell-style naming
- IO monads (use actors + async/await)

---

## See Also

- [CONCURRENCY.md](CONCURRENCY.md) - Swift 6 concurrency patterns
- [Swift Error Handling Documentation](https://docs.swift.org/swift-book/LanguageGuide/ErrorHandling.html)
- [Swift Result Type](https://developer.apple.com/documentation/swift/result)

---

**Document Version:** 1.0
**Created:** 2025-11-18
**Author:** Claude (Anthropic)
**Project:** Cupertino - Apple Documentation CLI & MCP Server
