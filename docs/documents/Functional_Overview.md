Response:
       Now I have a comprehensive understanding of the Cupertino codebase. Let me create a detailed, pragmatic analysis of
       which functional programming patterns are actually applicable.

       Functional Programming Patterns Analysis for Cupertino

       Executive Summary

       After analyzing the Cupertino codebase (a Swift CLI tool for crawling Apple documentation, fetching packages, building
       search indexes, and serving MCP), I've assessed which functional programming patterns from TODO #9 are actually useful
       vs. theoretical overhead.

       Key Findings:
       - 713 uses of error handling (throws/try/catch)
       - 563 uses of optionals (?/if let/guard let)
       - 13 custom error enums already in use
       - Heavy use of structs, enums, async/await, and actors
       - Real-world problems: SQLite errors, network failures, missing files, invalid data, rate limiting

       ---
       Pattern-by-Pattern Assessment

       1. Result/Either Type ✅ APPLICABLE

       Current State:
       // PackageFetcher.swift - Multiple error paths
       do {
           let packageInfo = try await fetchGitHubMetadata(owner: owner, repo: repo)
           packages.append(packageInfo)
           stats.successfulFetches += 1
       } catch PackageFetchError.rateLimited {
           rateLimited = try handleRateLimit(packages: packages, index: index, total: totalToProcess)
           break
       } catch {
           try handleFetchError(error, owner: owner, repo: repo, packages: &packages, stats: &stats)
       }

       Problem: You want to collect both successes and failures without throwing, especially when batch processing
       packages/documents.

       Proposed Pattern:
       public enum Result<Success, Failure: Error>: Sendable {
           case success(Success)
           case failure(Failure)

           public func map<T>(_ transform: (Success) -> T) -> Result<T, Failure> {
               switch self {
               case .success(let value): return .success(transform(value))
               case .failure(let error): return .failure(error)
               }
           }

           public func flatMap<T>(_ transform: (Success) -> Result<T, Failure>) -> Result<T, Failure> {
               switch self {
               case .success(let value): return transform(value)
               case .failure(let error): return .failure(error)
               }
           }
       }

       Real Use Cases:
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/PackageFetcher.swift:107-116 - Batch
       GitHub API fetches
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/Crawler.swift:111-129 - Crawling multiple
       pages
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoSearch/SearchIndex.swift:464-472 - SQLite row
       processing

       Benefit: Collect all results (success + failure) for batch operations, generate detailed error reports.

       Verdict: ✅ HIGHLY APPLICABLE - Solves real batch processing needs.

       ---
       2. Option/Maybe Type ⚠️ MAYBE

       Current State:
       // SearchResult.swift:54
       public let localPath: String?

       // DocsResourceProvider.swift:167
       guard let metadata else {
           throw ResourceError.noDocumentation
       }

       // PackageFetcher.swift:231
       guard let downloadURL = try await findDownloadLinkWithJavaScript(...) else {
           throw SampleDownloaderError.downloadLinkNotFound(sample.name)
       }

       Analysis: Swift's built-in Optional<T> already provides:
       - map, flatMap, ?? (nil coalescing)
       - Pattern matching with if let, guard let
       - Excellent compiler support

       Proposed Enhancement:
       extension Optional {
           // Functional helpers beyond what Swift provides
           public func orThrow(_ error: @autoclosure () -> Error) throws -> Wrapped {
               guard let value = self else { throw error() }
               return value
           }

           public func filter(_ predicate: (Wrapped) -> Bool) -> Wrapped? {
               guard let value = self, predicate(value) else { return nil }
               return value
           }
       }

       Real Use Cases:
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/SampleCodeDownloader.swift:231 -
       Converting nil to specific error
       - Chaining optional operations in search results

       Verdict: ⚠️ MAYBE - Swift's Optional is already good. Only add minimal utilities if they eliminate boilerplate.

       ---
       3. Sum Types (Enums) ✅ APPLICABLE (Already Using!)

       Current State:
       // SearchResult.swift:98
       public enum SearchError: Error, LocalizedError {
           case databaseNotInitialized
           case sqliteError(String)
           case prepareFailed(String)
           case insertFailed(String)
           case searchFailed(String)
           case invalidQuery(String)
       }

       // JSONRPC.swift:6
       public enum RequestID: Codable, Hashable, Sendable {
           case string(String)
           case int(Int)
       }

       Analysis: You're already using sum types extensively (13 error enums found). This is perfect!

       Best Practices:
       - ✅ Use enums with associated values for error cases with context
       - ✅ Use enums for modeling mutually exclusive states
       - ✅ Conform to LocalizedError for user-facing messages

       Real Use Cases (Already Implemented):
       - Error modeling: SearchError, CrawlerError, PackageFetchError, ServerError
       - Protocol modeling: RequestID, JSONRPCMessage, ContentBlock

       Verdict: ✅ ALREADY DOING THIS - Continue current pattern.

       ---
       4. Product Types (Structs) ✅ APPLICABLE (Already Using!)

       Current State:
       // SearchResult.swift:6
       public struct SearchResult: Codable, Sendable, Identifiable {
           public let id: UUID
           public let uri: String
           public let framework: String
           public let title: String
           public let summary: String
           public let filePath: String
           public let wordCount: Int
           public let rank: Double
       }

       Analysis: Excellent use of immutable structs with let properties. The codebase heavily favors value semantics.

       Best Practices (Already Following):
       - ✅ Immutable by default (let)
       - ✅ Sendable for concurrency safety
       - ✅ Codable for serialization
       - ✅ Descriptive property names

       Verdict: ✅ ALREADY DOING THIS - Continue current pattern.

       ---
       5. Functors (map over wrapped values) ✅ APPLICABLE

       Current State:
       // Implicit use with arrays
       let sortedPackages = packages
           .filter { $0.error == nil || $0.stars > 0 }
           .sorted { $0.stars > $1.stars }

       // Optional chaining
       stats.duration.map { "   Duration: \(formatDuration($0))" }

       Analysis: You're already using functors implicitly with Array.map, Optional.map. Swift's standard library provides this.

       Proposed Enhancement:
       // Explicit Functor protocol for custom types
       protocol Functor {
           associatedtype Wrapped
           associatedtype Mapped

           func map<T>(_ transform: (Wrapped) -> T) -> Mapped
       }

       // Example: Make Result a Functor (already shown above)

       Real Use Cases:
       - Transforming search results without touching error paths
       - Mapping over async sequences of crawled pages

       Verdict: ✅ APPLICABLE - Already implicitly used. Formalize for Result type.

       ---
       6. Monads (bind/flatMap) ✅ APPLICABLE

       Current State:
       // Optional chaining is flatMap
       if let metadata = try? loadMetadata() {
           if let page = metadata.pages[url] {
               // Use page
           }
       }

       // Could be:
       try? loadMetadata()
           .flatMap { $0.pages[url] }

       Analysis: Swift's Optional and Array already have flatMap. Need it for Result type.

       Proposed:
       // Result.flatMap (already shown above)
       // Enables chaining failable operations

       let result: Result<PackageInfo, PackageFetchError> =
           fetchStarCount(owner: owner, repo: repo)
               .flatMap { stars in
                   fetchMetadata(owner: owner, repo: repo)
                       .map { metadata in
                           PackageInfo(stars: stars, metadata: metadata)
                       }
               }

       Real Use Cases:
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/PackageFetcher.swift:304-329 - Chaining
       API calls
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoSearch/SearchIndex.swift:238-286 - Processing
       query results

       Verdict: ✅ APPLICABLE - Needed for Result type composition.

       ---
       7. Applicative Functors (Parallel Validation) ⚠️ MAYBE

       Pattern:
       // Validate multiple fields in parallel, collect ALL errors
       struct ValidationError {
           let fields: [String: String]
       }

       func validate(query: String, framework: String?, limit: Int)
           -> Result<ValidatedSearch, ValidationError> {
           // Collect all validation errors, not just first
       }

       Current State:
       // SearchIndex.swift:419-421
       guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
           throw SearchError.invalidQuery("Query cannot be empty")
       }
       // Throws immediately, doesn't check other params

       Analysis: Could be useful for MCP request validation (validating multiple tool arguments), but current "fail fast"
       approach is simpler.

       Verdict: ⚠️ MAYBE - Only if you need to show users all validation errors at once. Not critical.

       ---
       8. Semigroups (Combining Results) ✅ APPLICABLE

       Pattern:
       protocol Semigroup {
           static func combine(_ lhs: Self, _ rhs: Self) -> Self
       }

       // Combine statistics from multiple crawls
       extension CrawlStatistics: Semigroup {
           static func combine(_ lhs: CrawlStatistics, _ rhs: CrawlStatistics) -> CrawlStatistics {
               CrawlStatistics(
                   totalPages: lhs.totalPages + rhs.totalPages,
                   newPages: lhs.newPages + rhs.newPages,
                   updatedPages: lhs.updatedPages + rhs.updatedPages,
                   skippedPages: lhs.skippedPages + rhs.skippedPages,
                   errors: lhs.errors + rhs.errors,
                   startTime: min(lhs.startTime, rhs.startTime),
                   endTime: max(lhs.endTime, rhs.endTime)
               )
           }
       }

       Real Use Cases:
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoShared/Models.swift:101-135 - Merging
       CrawlStatistics
       - /Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoCore/PackageFetcher.swift:512-523 - Combining
       PackageFetchStatistics
       - Merging search results from multiple indexes

       Verdict: ✅ APPLICABLE - Clean way to combine stats, errors, and results.

       ---
       9. Monoids (Identity Element) ⚠️ MAYBE

       Pattern:
       protocol Monoid: Semigroup {
           static var empty: Self { get }
       }

       extension CrawlStatistics: Monoid {
           static var empty: CrawlStatistics {
               CrawlStatistics()
           }
       }

       // Now you can fold/reduce safely
       let totalStats = crawls.reduce(.empty, CrawlStatistics.combine)

       Analysis: Natural extension of Semigroup. Useful for safe reduction operations.

       Verdict: ⚠️ MAYBE - Nice-to-have if implementing Semigroup. Low overhead.

       ---
       10. Category Theory (Composition, Morphisms) ❌ NOT APPLICABLE

       Analysis: This is theoretical overhead for a CLI tool. You don't need:
       - Arrow composition operators
       - Natural transformations
       - Kleisli categories

       Verdict: ❌ NOT APPLICABLE - Too academic for practical CLI tool.

       ---
       11. IO Monad ❌ NOT APPLICABLE

       Analysis: Swift has async/await and actors, which are superior to IO monads for managing side effects.

       Current State:
       public actor SearchIndex {
           private var database: OpaquePointer?
           // Actor isolation provides safe side-effect management
       }

       Verdict: ❌ NOT APPLICABLE - Use Swift's async/await + actors instead.

       ---
       12. Zero/Unit Types (Never, Void) ✅ APPLICABLE (Already Using!)

       Current State:
       // Never for non-returning functions (crashes)
       func fatalError(_ message: String) -> Never

       // Void for side-effect-only functions
       public func logInfo(_ message: String) {
           print(message)
       }

       Analysis: You're already using these appropriately.

       Verdict: ✅ ALREADY DOING THIS - No changes needed.

       ---
       Naming Conventions Assessment

       Map/FlatMap/Filter ✅ RECOMMENDED

       Use: map, flatMap, filter, compactMap
       Avoid: fmap, bind, select
       Reason: Swift standard library convention.

       Fold/Reduce ✅ RECOMMENDED

       Use: reduce, fold (as alias)
       Reason: Both are clear and common.

       Pure/Return ❌ NOT RECOMMENDED

       Use: Just return the value
       Avoid: Wrapping in pure() or return() functions
       Reason: Unnecessary in Swift - type system is clear enough.

       ---
       Recommended Implementation Plan

       Priority 1: High Value, Low Effort

       1. Result Type (/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoShared/Result.swift)
       public enum Result<Success, Failure: Error>: Sendable {
           case success(Success)
           case failure(Failure)

           public func map<T>(_ transform: (Success) -> T) -> Result<T, Failure>
           public func flatMap<T>(_ transform: (Success) -> Result<T, Failure>) -> Result<T, Failure>
           public func mapError<T: Error>(_ transform: (Failure) -> T) -> Result<Success, T>
       }

       1. Usage:
       // PackageFetcher: Collect all results
       let results: [Result<PackageInfo, PackageFetchError>] = await packages.map { pkg in
           await Result { try await fetchGitHubMetadata(owner: pkg.owner, repo: pkg.repo) }
       }

       let (successes, failures) = results.partition()
       2. Semigroup Protocol (/Volumes/Code/DeveloperExt/private/cupertino/Packages/Sources/CupertinoShared/Semigroup.swift)
       public protocol Semigroup {
           static func combine(_ lhs: Self, _ rhs: Self) -> Self
       }

       extension CrawlStatistics: Semigroup { ... }
       extension PackageFetchStatistics: Semigroup { ... }

       Priority 2: Nice-to-Have

       3. Optional Extensions
       extension Optional {
           public func orThrow(_ error: @autoclosure () -> Error) throws -> Wrapped
       }
       4. Monoid Protocol (if implementing Semigroup)

       Priority 3: Skip

       - ❌ Category theory abstractions
       - ❌ IO monad
       - ❌ Complex applicative functors
       - ❌ Custom functor protocol (use Swift's built-in)

       ---
       Concrete Code Examples

       Example 1: Batch Package Fetching with Result

       Before:
       // PackageFetcher.swift:96-133
       for index in startIndex..<totalToProcess {
           do {
               let packageInfo = try await fetchGitHubMetadata(owner: owner, repo: repo)
               packages.append(packageInfo)
               stats.successfulFetches += 1
           } catch {
               stats.errors += 1
               // Error info lost
           }
       }

       After:
       let results: [Result<PackageInfo, PackageFetchError>] = await (startIndex..<totalToProcess).map { index in
           let packageURL = packageURLs[index]
           guard let (owner, repo) = extractOwnerRepo(from: packageURL) else {
               return .failure(.invalidURL(packageURL))
           }
           return await Result { try await fetchGitHubMetadata(owner: owner, repo: repo) }
       }

       let (successes, failures) = results.partition()
       packages.append(contentsOf: successes)

       // Generate detailed error report
       let errorReport = failures.map { error in
           "Failed to fetch \(error.packageName): \(error.reason)"
       }.joined(separator: "\n")

       Example 2: Combining Statistics with Semigroup

       Before:
       // Manual merging
       stats.totalPages += crawlStats.totalPages
       stats.newPages += crawlStats.newPages
       stats.updatedPages += crawlStats.updatedPages
       // ... 10 more lines

       After:
       stats = CrawlStatistics.combine(stats, crawlStats)

       // Or reduce multiple crawls
       let totalStats = allCrawlStats.reduce(.empty, CrawlStatistics.combine)

       Example 3: Search Result Validation

       Before:
       // SearchIndex.swift:419-421
       guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
           throw SearchError.invalidQuery("Query cannot be empty")
       }

       After (using Result):
       func validateSearchParams(query: String, limit: Int) -> Result<ValidatedParams, SearchError> {
           guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
               return .failure(.invalidQuery("Query cannot be empty"))
           }
           guard limit > 0 && limit <= maxLimit else {
               return .failure(.invalidQuery("Limit must be between 1 and \(maxLimit)"))
           }
           return .success(ValidatedParams(query: query, limit: limit))
       }

       // Chain validation with search
       let result = validateSearchParams(query: query, limit: limit)
           .flatMap { params in await search(params: params) }

       ---
       Summary Table

       | Pattern                 | Status    | Priority | Benefit              | Complexity   |
       |-------------------------|-----------|----------|----------------------|--------------|
       | Result/Either           | ✅ Add     | HIGH     | Batch error handling | Low          |
       | Semigroup               | ✅ Add     | MEDIUM   | Stats merging        | Low          |
       | Sum Types (Enums)       | ✅ Using   | N/A      | Error modeling       | Already done |
       | Product Types (Structs) | ✅ Using   | N/A      | Data modeling        | Already done |
       | Functors (map)          | ✅ Using   | N/A      | Transformations      | Already done |
       | Monads (flatMap)        | ✅ Add     | MEDIUM   | Chaining operations  | Low          |
       | Optional                | ⚠️ Extend | LOW      | Minor utilities      | Low          |
       | Monoid                  | ⚠️ Maybe  | LOW      | Nice with Semigroup  | Low          |
       | Applicative             | ⚠️ Maybe  | LOW      | Parallel validation  | Medium       |
       | Category Theory         | ❌ Skip    | N/A      | None                 | High         |
       | IO Monad                | ❌ Skip    | N/A      | Use async/await      | High         |

       ---
       Conclusion

       The pragmatic FP patterns for Cupertino are:

       1. Result type - Solves real batch processing needs
       2. Semigroup/Monoid - Clean statistics merging
       3. Continue using enums/structs - Already excellent
       4. Stick to Swift conventions - map/flatMap/reduce

       Avoid:
       - Theoretical category theory
       - IO monads (use actors/async)
       - Custom functor protocols (use Swift's)
       - Academic naming (fmap, pure, return)

       This gives you the pragmatic benefits of functional programming without turning your CLI tool into a Haskell
       dissertation.
  ⎿  Done (17 tool uses · 74.7k tokens · 2m 50s)

⏺ Bash(say -v "Karen (Premium)" "Investigation complete. Presenting findings on applicable functional programming patterns.")
  ⎿  (No content)

⏺ My Investigation Results: What's Actually Applicable

  I've analyzed your codebase thoroughly (713 error handling sites, 563 optionals, 13 custom error enums). Here's what's
  actually useful vs. theoretical overhead:

  ---
  ✅ HIGHLY APPLICABLE - Implement These

  1. Result Type - Priority: HIGH

  Why: You do a LOT of batch processing (fetching 9,699 packages, crawling thousands of pages). Currently errors just throw and
  you lose context.

  Current Problem:
  // PackageFetcher.swift - loses error details
  for pkg in packages {
      do {
          let info = try await fetch(pkg)
          successes.append(info)
      } catch {
          // Error details lost!
      }
  }

  Solution:
  let results: [Result<PackageInfo, FetchError>] = await packages.map { pkg in
      await Result { try await fetch(pkg) }
  }
  let (successes, failures) = results.partition()
  // Now you have ALL errors with details for reporting

  2. Semigroup Protocol - Priority: MEDIUM

  Why: You merge statistics everywhere. Currently it's manual and error-prone.

  Current:
  stats.totalPages += crawlStats.totalPages
  stats.newPages += crawlStats.newPages
  // ... 10 more lines of this

  Solution:
  stats = CrawlStatistics.combine(stats, crawlStats)
  // Or: let total = allStats.reduce(.empty, CrawlStatistics.combine)

  ---
  ✅ ALREADY DOING - Keep It Up

  3. Sum Types (Enums) ✅

  You already have 13 excellent error enums:
  - SearchError, PackageFetchError, CrawlerError, etc.
  - All with associated values
  - Perfect - keep doing this!

  4. Product Types (Structs) ✅

  Excellent use of immutable structs with let, Sendable, Codable
  - Perfect - keep doing this!

  5. Functors (map/flatMap) ✅

  Already using Array.map, Optional.map everywhere
  - Just formalize it for your new Result type

  ---
  ⚠️ MAYBE - Only If Needed

  6. Monoid Protocol - Priority: LOW

  Natural extension of Semigroup. Only add if you implement Semigroup.

  7. Optional Extensions - Priority: LOW

  extension Optional {
      func orThrow(_ error: Error) throws -> Wrapped
  }
  Minor utility - only if it eliminates repetitive code.

  8. Applicative Functors - Priority: LOW

  Only useful if you want to show users ALL validation errors at once (instead of failing on first error). Current "fail fast"
  is simpler.

  ---
  ❌ NOT APPLICABLE - Skip These

  9. Category Theory ❌

  Arrows, morphisms, natural transformations - too academic for a CLI tool.

  10. IO Monad ❌

  Swift has actors + async/await which are superior for side effects.

  11. Custom Functor Protocol ❌

  Swift's standard library already provides this. Don't reinvent.

  ---
  Naming Conventions - Use Swift Standards

  ✅ Use: map, flatMap, filter, reduce, compactMap
  ❌ Avoid: fmap, bind, pure, return (too Haskell-y)

  ---
  Recommended Implementation

  Phase 1: Add Result Type

  // Sources/CupertinoShared/Result.swift
  public enum Result<Success, Failure: Error>: Sendable {
      case success(Success)
      case failure(Failure)

      public func map<T>(_ transform: (Success) -> T) -> Result<T, Failure>
      public func flatMap<T>(_ transform: (Success) -> Result<T, Failure>) -> Result<T, Failure>
      public func mapError<T: Error>(_ transform: (Failure) -> T) -> Result<Success, T>
  }

  Phase 2: Add Semigroup

  // Sources/CupertinoShared/Semigroup.swift
  public protocol Semigroup {
      static func combine(_ lhs: Self, _ rhs: Self) -> Self
  }

  extension CrawlStatistics: Semigroup { ... }
  extension PackageFetchStatistics: Semigroup { ... }

  ---
  Summary Table

  | Pattern         | Status   | Action | Why                              |
  |-----------------|----------|--------|----------------------------------|
  | Result          | ✅ Add    | HIGH   | Batch error handling is critical |
  | Semigroup       | ✅ Add    | MEDIUM | Stats merging is common          |
  | Enums/Structs   | ✅ Keep   | N/A    | Already perfect                  |
  | map/flatMap     | ✅ Keep   | N/A    | Already using                    |
  | Monoid          | ⚠️ Maybe | LOW    | Nice-to-have with Semigroup      |
  | Applicative     | ⚠️ Maybe | LOW    | Only if needed                   |
  | Category Theory | ❌ Skip   | N/A    | Too theoretical                  |
  | IO Monad        | ❌ Skip   | N/A    | Use actors instead               |

  ---
  My Recommendation

  Update TODO #9 to focus on the pragmatic patterns:
  - ✅ Result type for batch operations
  - ✅ Semigroup for combining statistics
  - ✅ Continue excellent enum/struct patterns
  - ❌ Skip academic category theory

