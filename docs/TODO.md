#  TODO:

## ✅ 1. SampleCodeCatalog - All Known Apple Sample Files (COMPLETED)

- ✅ convert it to json
- ✅ add date (last crawled 17.11.2025.)
- ✅ add to resources
- ✅ add test to confirm reading is correct
- ✅ BONUS: Added priority packages catalog (31 Apple + 5 ecosystem packages)

## ✅ 2. All Swift Packages (COMPLETED)
- ✅ currnetly I have crawled all github swift packages
- ✅ the operation first crawled Swift Pacjage Index
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

- ✅ Created `docs/commands/` directory
- ✅ Documented all 3 commands in separate files:
  - `crawl.md` - Web crawling with WKWebView
  - `fetch.md` - Resource fetching (packages, sample code)
  - `index.md` - FTS5 search index building
- ✅ Created `README.md` with quick start, workflows, and examples
- ✅ Included default locations, advanced features, and typical workflows

## 5. Hardcoded folder names and file names
- we need those
- those are artefacts we create
- we need to know where to find things
- follow the naming now in /Volumes/Code/DeveloperExt/cupertino_test/  for folder names
- I want the same folder-based documentation as for commands


## 6. fetch authenticate does not work
- it never opens the safari browser, I opened it manually
- investigate how other terminal comamnds are doing it
- maybe search GitHub for code examples
