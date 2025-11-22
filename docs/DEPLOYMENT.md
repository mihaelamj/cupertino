# Deployment Guide

Complete guide for deploying Cupertino via Homebrew and automating releases with GitHub Actions.

## Table of Contents

1. [Overview](#overview)
2. [Homebrew Distribution](#homebrew-distribution)
   - [What is Homebrew?](#what-is-homebrew)
   - [Quick Start](#quick-start)
   - [Creating the Formula](#creating-the-formula)
   - [Building Bottles](#building-bottles)
   - [Testing Locally](#testing-locally)
   - [Publishing Options](#publishing-options)
   - [Complete Workflow](#complete-workflow)
   - [Best Practices](#best-practices)
3. [CI/CD with GitHub Actions](#cicd-with-github-actions)
   - [Build & Test Workflow](#1-build--test-workflow)
   - [SwiftLint Workflow](#2-swiftlint-workflow)
   - [Daily Documentation Check](#3-daily-documentation-check)
   - [Release Workflow](#4-release-workflow)
   - [GitHub Repository Settings](#github-repository-settings)
   - [Automated Documentation Updates](#automated-documentation-updates-strategy)
   - [Project Badges](#project-statistics-badges)
4. [Release Checklist](#release-checklist)
5. [Resources](#resources)

---

## Overview

This guide covers two key aspects of deploying Cupertino:

1. **Homebrew Distribution** - Package and distribute Cupertino through Homebrew, the most popular macOS package manager
2. **GitHub Actions CI/CD** - Automate builds, tests, and releases with GitHub Actions workflows

Together, these enable automated releases and easy installation for end users.

---

## Homebrew Distribution

### What is Homebrew?

[Homebrew](https://brew.sh) is the most popular package manager for macOS. Creating a Homebrew formula allows users to install Cupertino with a single command:

```bash
brew install docsucker
```

Instead of manually building from source.

---

### Quick Start

> **Note**: All `make` commands in this guide can be run from the **root directory** of the repository. A wrapper Makefile in the root delegates to `Packages/Makefile`, so you don't need to `cd Packages` first.

#### Option 1: Install from Local Build

```bash
# From root directory
make install

# Or from Packages subdirectory
cd Packages
make install

# Install to custom location
make install PREFIX=~/.local
```

#### Option 2: Create Homebrew Tap (Recommended)

Create your own Homebrew tap for easy distribution:

```bash
# 1. Create tap repository
mkdir -p ~/homebrew-tap
cd ~/homebrew-tap
git init

# 2. Create formula (see template below)
mkdir -p Formula
# Create Formula/docsucker.rb

# 3. Push to GitHub
git remote add origin https://github.com/YOUR_USERNAME/homebrew-tap.git
git add .
git commit -m "Add docsucker formula"
git push -u origin main

# 4. Users can now install with:
brew tap YOUR_USERNAME/tap
brew install docsucker
```

---

### Creating the Formula

#### Formula Template

Create `Formula/docsucker.rb`:

```ruby
class Cupertino < Formula
  desc "Apple Documentation Crawler & MCP Server"
  homepage "https://github.com/YOUR_USERNAME/cupertino"
  url "https://github.com/YOUR_USERNAME/cupertino/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "SHA256_HASH_OF_TARBALL"  # Get with: shasum -a 256 tarball.tar.gz
  license "MIT"  # Or your chosen license
  head "https://github.com/YOUR_USERNAME/cupertino.git", branch: "main"

  # Dependencies
  depends_on "swift" => :build
  depends_on xcode: ["16.0", :build]
  depends_on :macos => :sequoia  # macOS 15+

  def install
    # Build executables
    system "swift", "build",
           "--configuration", "release",
           "--disable-sandbox",
           "--build-path", ".build"

    # Install binaries
    bin.install ".build/release/docsucker"
    bin.install ".build/release/cupertino-mcp"

    # Install documentation
    doc.install "README.md"
    doc.install "DOCSUCKER_CLI_README.md"
    doc.install "MCP_SERVER_README.md"
    doc.install "TESTING_GUIDE.md"
  end

  def caveats
    <<~EOS
      Cupertino has been installed!

      📚 CLI Usage:
        Download Apple documentation:
          cupertino fetch --max-pages 15000 --output-dir ~/.docsucker/docs

        Download Swift Evolution proposals:
          cupertino fetch-evolution --output-dir ~/.docsucker/swift-evolution

      🤖 MCP Server Setup:
        1. Start server:
           cupertino-mcp serve

        2. Configure Claude Desktop:
           Edit ~/Library/Application Support/Claude/claude_desktop_config.json:
           {
             "mcpServers": {
               "cupertino": {
                 "command": "#{bin}/cupertino-mcp",
                 "args": ["serve"]
               }
             }
           }

        3. Restart Claude Desktop

      📖 Documentation:
        #{doc}/README.md
        #{doc}/DOCSUCKER_CLI_README.md
        #{doc}/MCP_SERVER_README.md

      ⚠️  Requirements:
        - macOS 15+ (Sequoia)
        - ~2-3 GB disk space for full Apple documentation
        - Internet connection for initial download
    EOS
  end

  test do
    # Test CLI help
    assert_match "Apple Documentation Crawler", shell_output("#{bin}/docsucker --help")
    assert_match "1.0.0", shell_output("#{bin}/docsucker --version")

    # Test MCP help
    assert_match "MCP Server", shell_output("#{bin}/cupertino-mcp --help")
    assert_match "1.0.0", shell_output("#{bin}/cupertino-mcp --version")

    # Test small crawl (integration test)
    testdir = testpath/"test-output"
    system bin/"cupertino", "crawl",
           "--start-url", "https://developer.apple.com/documentation/swift/array",
           "--max-pages", "1",
           "--max-depth", "0",
           "--output-dir", testdir,
           "--force"

    assert_predicate testdir, :exist?, "Output directory should exist"

    # Check that markdown file was created (in subdirectory)
    markdown_files = Dir.glob("#{testdir}/**/*.md")
    assert !markdown_files.empty?, "Should have created at least one markdown file"
  end
end
```

#### Getting the SHA256 Hash

```bash
# Create release archive (from root directory)
make archive

# This creates: Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# Get SHA256
shasum -a 256 Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# Copy the hash into your formula
```

---

### Building Bottles

Homebrew bottles are pre-compiled binaries for faster installation.

#### Using the Makefile

```bash
# Build bottle (from root directory)
make bottle

# This creates:
# Packages/docsucker-1.0.0.arm64_monterey.bottle.tar.gz

# Get SHA256 for bottle
shasum -a 256 Packages/docsucker-1.0.0.arm64_monterey.bottle.tar.gz
```

#### Adding Bottles to Formula

```ruby
class Cupertino < Formula
  # ... (desc, homepage, etc.) ...

  bottle do
    root_url "https://github.com/YOUR_USERNAME/cupertino/releases/download/v1.0.0"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "BOTTLE_SHA256_HERE"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "BOTTLE_SHA256_HERE"
    sha256 cellar: :any_skip_relocation, ventura:       "BOTTLE_SHA256_HERE"
  end

  # ... (rest of formula) ...
end
```

#### Building Bottles for Multiple macOS Versions

```bash
# On macOS 15 (Sequoia)
make bottle
# → docsucker-1.0.0.arm64_sequoia.bottle.tar.gz

# On macOS 14 (Sonoma)
make bottle
# → docsucker-1.0.0.arm64_sonoma.bottle.tar.gz

# On macOS 13 (Ventura)
make bottle
# → docsucker-1.0.0.arm64_ventura.bottle.tar.gz
```

---

### Testing Locally

#### Test Formula Before Publishing

```bash
# 1. Audit formula
brew audit --new-formula Formula/docsucker.rb

# 2. Style check
brew style Formula/docsucker.rb

# 3. Install from formula
brew install --build-from-source Formula/docsucker.rb

# 4. Run tests
brew test docsucker

# 5. Verify installation
cupertino --version
cupertino-mcp --version

# 6. Test functionality
cupertino fetch --max-pages 1 --output-dir /tmp/test-docs

# 7. Uninstall
brew uninstall docsucker
```

#### Common Issues

**Issue: Swift version mismatch**

```bash
# Check Swift version
swift --version

# Update Xcode Command Line Tools
xcode-select --install
```

**Issue: Build fails with "cannot find module"**

```bash
# Clean and rebuild
cd Packages
swift package clean
brew install --build-from-source --verbose Formula/docsucker.rb
```

**Issue: Tests fail**

```bash
# Run tests manually
cd Packages
swift test

# Check specific test
swift test --filter testDownloadRealAppleDocPage
```

---

### Publishing Options

#### Option 1: Personal Tap (Easiest)

Create your own Homebrew tap for easy maintenance and distribution.

##### Step 1: Create Tap Repository

```bash
# Create repository on GitHub: homebrew-tap
# Clone it locally
git clone https://github.com/YOUR_USERNAME/homebrew-tap.git
cd homebrew-tap

# Create Formula directory
mkdir -p Formula
```

##### Step 2: Add Formula

```bash
# Copy formula
cp /path/to/docsucker.rb Formula/

# Commit
git add Formula/docsucker.rb
git commit -m "Add docsucker formula"
git push
```

##### Step 3: Users Install

```bash
# Users tap your repository
brew tap YOUR_USERNAME/tap

# Install docsucker
brew install docsucker

# Update
brew update
brew upgrade docsucker
```

##### Step 4: Release Updates

```bash
# 1. Update version in formula
# 2. Update URL and SHA256
# 3. Commit and push
git add Formula/docsucker.rb
git commit -m "docsucker 1.1.0"
git push

# Users get updates with:
brew update
brew upgrade docsucker
```

#### Option 2: Submit to Homebrew Core (Advanced)

Submit to official [homebrew-core](https://github.com/Homebrew/homebrew-core) for wider distribution.

##### Requirements

- Project must be stable and well-maintained
- Must have a tagged release on GitHub
- Formula must pass all audits
- Must build bottles for all supported macOS versions
- Must have comprehensive tests

##### Process

1. **Fork homebrew-core**:
   ```bash
   # Fork https://github.com/Homebrew/homebrew-core on GitHub
   git clone https://github.com/YOUR_USERNAME/homebrew-core.git
   cd homebrew-core
   ```

2. **Create formula**:
   ```bash
   # Use Homebrew's formula creator
   brew create https://github.com/YOUR_USERNAME/cupertino/archive/refs/tags/v1.0.0.tar.gz

   # Edit the generated formula
   brew edit docsucker
   ```

3. **Test thoroughly**:
   ```bash
   brew audit --new-formula --online docsucker
   brew style docsucker
   brew install --build-from-source docsucker
   brew test docsucker
   brew linkage docsucker
   ```

4. **Build bottles**:
   ```bash
   brew install --build-bottle docsucker
   brew bottle docsucker
   ```

5. **Submit PR**:
   ```bash
   git add Formula/docsucker.rb
   git commit -m "docsucker 1.0.0 (new formula)"
   git push origin main

   # Create PR on GitHub
   ```

6. **Wait for review** - Homebrew maintainers will review and merge if approved

#### Option 3: Cask for Pre-built Binaries (Alternative)

If you want to distribute pre-built binaries instead of building from source:

```ruby
cask "cupertino" do
  version "1.0.0"
  sha256 "SHA256_OF_ZIP"

  url "https://github.com/YOUR_USERNAME/cupertino/releases/download/v#{version}/docsucker-#{version}-macos.zip"
  name "Cupertino"
  desc "Apple Documentation Crawler & MCP Server"
  homepage "https://github.com/YOUR_USERNAME/cupertino"

  binary "cupertino"
  binary "cupertino-mcp"
end
```

---

### Complete Workflow

#### Initial Setup

```bash
# 1. Tag release in Git (from root directory)
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0

# 2. Create release archive
make archive
# Creates: Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# 3. Upload to GitHub Releases
# Go to: https://github.com/YOUR_USERNAME/cupertino/releases/new
# - Tag: v1.0.0
# - Title: Cupertino 1.0.0
# - Upload: Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# 4. Get SHA256
shasum -a 256 Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz
# Copy this hash

# 5. Create formula
# Create homebrew-tap repository on GitHub
git clone https://github.com/YOUR_USERNAME/homebrew-tap.git
cd homebrew-tap
mkdir -p Formula

# 6. Create Formula/docsucker.rb (use template above)
# - Set URL to GitHub release tarball
# - Set SHA256 from step 4

# 7. Commit formula
git add Formula/docsucker.rb
git commit -m "Add docsucker 1.0.0"
git push

# 8. Test installation
brew tap YOUR_USERNAME/tap
brew install docsucker --build-from-source
brew test docsucker

# 9. Build and upload bottle (optional)
brew install --build-bottle docsucker
brew bottle docsucker
# Upload bottle to GitHub Releases
# Update formula with bottle SHA256

# 10. Done! Users can now install with:
brew tap YOUR_USERNAME/tap
brew install docsucker
```

#### Release Updates

```bash
# 1. Update version in code
# - Packages/Sources/CupertinoShared/Configuration.swift
# - Update version to 1.1.0

# 2. Commit and tag (from root directory)
git add .
git commit -m "Release 1.1.0"
git tag -a v1.1.0 -m "Release 1.1.0"
git push origin v1.1.0

# 3. Create archive
make archive
# Creates: Packages/docsucker-1.1.0-arm64-apple-darwin.tar.gz

# 4. Upload to GitHub Releases

# 5. Update formula
cd homebrew-tap
# Update Formula/docsucker.rb:
#   - url: v1.1.0
#   - sha256: new hash
git add Formula/docsucker.rb
git commit -m "docsucker 1.1.0"
git push

# 6. Users upgrade with:
brew update
brew upgrade docsucker
```

---

### Best Practices

#### Versioning

- Use semantic versioning (1.0.0, 1.1.0, 2.0.0)
- Tag releases in Git
- Update version in code before tagging
- Create GitHub releases for each version

#### Formula Maintenance

- Keep formula simple and readable
- Test on multiple macOS versions
- Provide helpful caveats for post-install setup
- Include comprehensive tests
- Document dependencies clearly

#### Documentation

- Maintain clear README files
- Include installation instructions
- Provide usage examples
- Document MCP integration steps

#### Testing

```bash
# Always test before publishing:
brew audit --new-formula Formula/docsucker.rb
brew style Formula/docsucker.rb
brew install --build-from-source Formula/docsucker.rb
brew test docsucker
brew linkage docsucker

# Test on clean system (VM or container)
```

---

## CI/CD with GitHub Actions

Automate builds, tests, linting, and releases with GitHub Actions workflows.

### 1. Build & Test Workflow

**Purpose:** Build project on every push/PR to ensure it compiles

**File:** `.github/workflows/build.yml`

```yaml
name: Build

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    name: Build on macOS
    runs-on: macos-14  # macOS 14 (Sonoma) with Xcode 15+

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Swift
      uses: swift-actions/setup-swift@v2
      with:
        swift-version: '6.2'

    - name: Swift version
      run: swift --version

    - name: Build
      run: |
        cd Packages
        swift build --configuration release

    - name: Run tests
      run: |
        cd Packages
        swift test

    - name: Archive binaries (on main branch)
      if: github.ref == 'refs/heads/main'
      run: |
        cd Packages
        swift build --configuration release
        mkdir -p artifacts
        cp .build/release/cupertino artifacts/
        cp .build/release/cupertino-mcp artifacts/

    - name: Upload artifacts
      if: github.ref == 'refs/heads/main'
      uses: actions/upload-artifact@v4
      with:
        name: cupertino-binaries
        path: Packages/artifacts/
```

---

### 2. SwiftLint Workflow

**Purpose:** Enforce code quality on PRs

**File:** `.github/workflows/swiftlint.yml`

```yaml
name: SwiftLint

on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]

jobs:
  swiftlint:
    name: SwiftLint Check
    runs-on: macos-14

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Install SwiftLint
      run: brew install swiftlint

    - name: Run SwiftLint
      run: |
        cd Packages
        swiftlint lint --strict
```

---

### 3. Daily Documentation Check

**Purpose:** Automatically check for documentation updates daily

**File:** `.github/workflows/daily-check.yml`

```yaml
name: Daily Docs Check

on:
  schedule:
    # Run at 2 AM UTC daily
    - cron: '0 2 * * *'
  workflow_dispatch:  # Allow manual trigger

jobs:
  check-docs:
    name: Check for Documentation Updates
    runs-on: macos-14

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Swift
      uses: swift-actions/setup-swift@v2
      with:
        swift-version: '6.2'

    - name: Build cupertino
      run: |
        cd Packages
        swift build --configuration release

    - name: Install cupertino
      run: |
        sudo cp Packages/.build/release/cupertino /usr/local/bin/
        sudo cp Packages/.build/release/cupertino-mcp /usr/local/bin/

    - name: Run fast check
      id: check
      run: |
        # Fast check for changes (once Phase 5b is implemented)
        cupertino check --output /tmp/changes.json --no-delay || true

        # Count changes
        if [ -f /tmp/changes.json ]; then
          NEW=$(jq '.new | length' /tmp/changes.json)
          MODIFIED=$(jq '.modified | length' /tmp/changes.json)
          echo "new=$NEW" >> $GITHUB_OUTPUT
          echo "modified=$MODIFIED" >> $GITHUB_OUTPUT
        else
          echo "new=0" >> $GITHUB_OUTPUT
          echo "modified=0" >> $GITHUB_OUTPUT
        fi

    - name: Create issue if significant changes
      if: steps.check.outputs.new > 50 || steps.check.outputs.modified > 100
      uses: actions/github-script@v7
      with:
        script: |
          const new_count = ${{ steps.check.outputs.new }};
          const modified_count = ${{ steps.check.outputs.modified }};

          github.rest.issues.create({
            owner: context.repo.owner,
            repo: context.repo.repo,
            title: `Documentation changes detected: ${new_count} new, ${modified_count} modified`,
            body: `
## Documentation Update Detected

**Date:** ${new Date().toISOString()}

**Changes:**
- 🆕 New pages: ${new_count}
- ✏️ Modified pages: ${modified_count}

Consider running a full update to capture these changes.

\`\`\`bash
cupertino update
\`\`\`
            `,
            labels: ['documentation', 'automated']
          });

    - name: Comment on existing issues
      if: steps.check.outputs.new > 0 || steps.check.outputs.modified > 0
      run: |
        echo "Found ${{ steps.check.outputs.new }} new and ${{ steps.check.outputs.modified }} modified pages"
```

---

### 4. Release Workflow

**Purpose:** Automate releases when tags are pushed

**File:** `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'  # Trigger on version tags (e.g., v1.0.0)

jobs:
  release:
    name: Create Release
    runs-on: macos-14

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Swift
      uses: swift-actions/setup-swift@v2
      with:
        swift-version: '6.2'

    - name: Build release binaries
      run: |
        cd Packages
        swift build --configuration release

    - name: Create artifacts
      run: |
        mkdir -p release
        cp Packages/.build/release/cupertino release/
        cp Packages/.build/release/cupertino-mcp release/
        cd release
        tar -czf cupertino-${{ github.ref_name }}-macos.tar.gz cupertino cupertino-mcp

    - name: Create Release
      uses: softprops/action-gh-release@v1
      with:
        files: release/cupertino-${{ github.ref_name }}-macos.tar.gz
        generate_release_notes: true
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

### GitHub Repository Settings

#### Required Secrets

None required for basic workflows. All use `GITHUB_TOKEN` which is automatically provided.

#### Branch Protection Rules

For `main` branch:
- Require pull request reviews before merging
- Require status checks to pass:
  - Build
  - SwiftLint
- Require branches to be up to date before merging

---

### Automated Documentation Updates Strategy

#### Option 1: Notification Only (Recommended)

**What it does:**
- Daily check for documentation changes
- Creates GitHub issue if significant changes detected
- User manually runs update when ready

**Pros:**
- No risk of bad data
- User controls when to update
- Transparent process

**Cons:**
- Requires manual intervention

#### Option 2: Automated Update (Advanced)

**What it does:**
- Daily check + automatic update if changes found
- Commits updated docs to repository
- Creates PR for review

**Implementation:**
```yaml
- name: Run update if changes detected
  if: steps.check.outputs.new > 10
  run: |
    cupertino update --only-changed /tmp/changes.json
    cupertino build-index

- name: Create PR with updates
  uses: peter-evans/create-pull-request@v5
  with:
    title: "docs: Update documentation (${{ steps.check.outputs.new }} new pages)"
    body: |
      Automated documentation update

      - New pages: ${{ steps.check.outputs.new }}
      - Modified pages: ${{ steps.check.outputs.modified }}
    branch: automated-docs-update
    commit-message: "Update Apple documentation"
```

**Pros:**
- Fully automated
- Always up-to-date

**Cons:**
- Requires storing docs in git (large repo size)
- Potential for bad data if Apple docs change format

**Recommendation:** Use Option 1 (notification only)

---

### Project Statistics Badges

Add badges to README.md for project visibility:

```markdown
# AppleCupertino

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%2010.15%2B-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Build Status](https://github.com/mmj/cupertino/workflows/Build/badge.svg)
![Latest Release](https://img.shields.io/github/v/release/mmj/cupertino)

> Crawl and index Apple developer documentation for AI agent consumption
```

#### Dynamic Badges (Updated by Scripts)

Create a script that updates badge values:

```bash
#!/bin/bash
# .github/scripts/update-badges.sh

# Count docs
DOCS_COUNT=$(find /Volumes/Code/DeveloperExt/appledocsucker/docs -name "*.md" | wc -l | tr -d ' ')

# Count samples
SAMPLES_COUNT=$(find /Volumes/Code/DeveloperExt/appledocsucker/sample-code -name "*.zip" | wc -l | tr -d ' ')

# Count proposals
PROPOSALS_COUNT=$(find /Volumes/Code/DeveloperExt/appledocsucker/swift-evolution -name "*.md" | wc -l | tr -d ' ')

# Update gist or endpoint.json for shields.io dynamic badges
echo "{
  \"schemaVersion\": 1,
  \"label\": \"documentation\",
  \"message\": \"${DOCS_COUNT}+ pages\",
  \"color\": \"success\"
}" > docs-badge.json
```

Then use shields.io endpoint badge:
```markdown
![Docs](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/mmj/cupertino/main/docs-badge.json)
```

---

## Release Checklist

Use this checklist for each release:

### Pre-Release

- [ ] Update version in `Packages/Sources/CupertinoShared/Configuration.swift`
- [ ] Update CHANGELOG.md with release notes
- [ ] Run all tests: `cd Packages && swift test`
- [ ] Run SwiftLint: `cd Packages && swiftlint lint --strict`
- [ ] Build release binaries: `make archive`
- [ ] Test installation locally

### Release

- [ ] Commit version changes: `git commit -m "Release X.Y.Z"`
- [ ] Tag release: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
- [ ] Wait for GitHub Actions to build and create release
- [ ] Verify release artifacts on GitHub

### Homebrew

- [ ] Get SHA256 of release tarball
- [ ] Update Homebrew formula (url, sha256, version)
- [ ] Test formula: `brew install --build-from-source Formula/docsucker.rb`
- [ ] Run formula tests: `brew test docsucker`
- [ ] Commit formula: `git commit -m "docsucker X.Y.Z"`
- [ ] Push to tap: `git push`

### Post-Release

- [ ] Test user installation: `brew upgrade docsucker`
- [ ] Update documentation if needed
- [ ] Announce release (if applicable)
- [ ] Monitor for issues

### Optional: Build Bottles

- [ ] Build bottles on macOS Sequoia, Sonoma, Ventura
- [ ] Upload bottles to GitHub Releases
- [ ] Update formula with bottle SHA256s
- [ ] Push updated formula

---

## Resources

### Homebrew

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)
- [Creating Taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Homebrew Bottles](https://docs.brew.sh/Bottles)
- [Swift in Homebrew](https://github.com/Homebrew/homebrew-core/search?q=language%3ARuby+swift&type=code)

### GitHub Actions

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Swift Actions](https://github.com/swift-actions)
- [Creating Releases](https://docs.github.com/en/repositories/releasing-projects-on-github)
- [Workflow Syntax](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)

### Swift & macOS

- [Swift Package Manager](https://swift.org/package-manager/)
- [SwiftLint](https://github.com/realm/SwiftLint)
- [Semantic Versioning](https://semver.org/)

---

**Last updated:** 2025-11-22
**Status:** Production deployment guide
