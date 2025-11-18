#  TODO:

## ✅ 1. SampleCodeCatalog - All Known Apple Sample Files (COMPLETED)

- ✅ convert it to json
- ✅ add date (last crawled 17.11.2025.)
- ✅ add to resources
- ✅ add test to confirm reading is correct
- ✅ BONUS: Added priority packages catalog (31 Apple + 5 ecosystem packages)

## ✅ 2. All Swift Packages (COMPLETED)
- ✅ currently I have crawled all github swift packages
- ✅ the operation first crawled Swift Package Index
- ✅ then it crawled package metadata from GitHub
- ✅ the data from that crawl is available in folder:
/Volumes/Code/DeveloperExt/cupertino_test/packages/checkpoint.json
- ✅ that file should also be copied to the project - resources
- ✅ renamed to swift-packages-catalog.json
- ✅ date added (last crawled 17.11.2025.)

## ✅ 3. Question: Sample Code URL Structure (ANSWERED)

**Q: Why do sample codes have URLs like `/documentation/GameKit/...` with hardcoded "documentation"?**

**A: This is Apple's standard URL structure, NOT hardcoded by us.**

Investigation results:
- ✅ ALL 606 sample code entries start with `/documentation/`
- ✅ This is Apple's base path: `developer.apple.com/documentation/`
- ✅ Format: `/documentation/{Framework}/{sample-project-name}`
- ✅ Verified: All 607 zip files in cupertino_test/sample-code match catalog entries
- ✅ URL structure is consistent and correct across the entire catalog

The "documentation" prefix is Apple's URL convention, not something we hardcode.

## ✅ 4. Document Commands (COMPLETED)

- ✅ Created `docs/commands/` directory with folder-based structure
- ✅ Each command is a folder: `crawl/`, `fetch/`, `index/`
- ✅ Each option is a separate file within the command folder
- ✅ Complex options like `--type` are folders with files for each value
- ✅ Total: 30 command documentation files
- ✅ Documented `--type all` for crawl (crawls docs, swift, evolution in parallel)

## ✅ 5. Document Artifacts - Hardcoded folder names and file names (COMPLETED)

- ✅ Created `docs/artifacts/` directory with folder-based structure
- ✅ Documented all generated folders: docs/, swift-org/, swift-evolution/, sample-code/, packages/
- ✅ Documented all generated files: metadata.json, checkpoint.json, search.db
- ✅ Used real filenames from /Volumes/Code/DeveloperExt/cupertino_test/
- ✅ Each artifact has detailed README with structure, examples, and usage
- ✅ Total: 9 artifact documentation files
- ✅ Reorganized structure: moved metadata.json and checkpoint.json to respective folders
- ✅ All examples use actual filename patterns (e.g., documentation_swift_array.md)

## 6. Each whole command must be atomic
- that means it must be able to be executed independently of other commands
- now, we do have dependent commands, but hopefully we moved dependencies to the resources files, with prefetched resources
- that is important so that:
  - each command can be executed alone
  - each command can be executed in parallel with other commands
  - each command can be tested alone
  - each command can be tested in parallel with other commands
  - all of this applies to parallel execution as well

## 7. We don't have clearly defined commands to update embedded resources:
- maybe we do, but it certainly is not clear
- we must make it more intuitive and clear
- updating all swift packages
- updating all apple sample sources
- there is always a possibility that we will need to add more pre-fetched resources

## 8. We must refactor commands
- the current architecture is (probably) redundant
- it is certainly complicated
- I feel it is incomplete
- before refactoring, TODO items 6 and 7 must be done
- then we must agree on the:
    - architecture
    - functionality
    - confirm/change naming
    - agree in detail on expected results

## 9. Implement error handling improvements

- Implement Semigroup protocol for statistics merging (`CrawlStatistics`, `PackageFetchStatistics`)
- Consider Optional extensions if boilerplate reduction is significant
- See [docs/ERROR_HANDLING.md](ERROR_HANDLING.md) for detailed design and rationale

**Summary from design doc:**
- Primary approach: Use `async throws` for 95% of code
- Result type: Only use for `TaskGroup.nextResult()` parallel error collection
- Continue using: Sum types (enums), product types (structs), map/flatMap
- New pattern: Semigroup for combining statistics




