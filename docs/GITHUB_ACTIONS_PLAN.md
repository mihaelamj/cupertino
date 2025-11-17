# AppleCupertino - GitHub Actions & Badges Plan

## README Badges (Phase 7a)

### Badges to Add

Add these at the top of README.md:

```markdown
# AppleCupertino

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%2010.15%2B-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Build Status](https://github.com/mmj/cupertino/workflows/Build/badge.svg)
![Latest Release](https://img.shields.io/github/v/release/mmj/cupertino)

> Crawl and index Apple developer documentation for AI agent consumption
```

### Badge Details

**Swift Version:**
```markdown
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
```

**Platforms:**
```markdown
![Platform](https://img.shields.io/badge/Platform-macOS%2010.15%2B-blue.svg)
![macCatalyst](https://img.shields.io/badge/Catalyst-13.0%2B-blue.svg)
![iOS](https://img.shields.io/badge/iOS-13.0%2B-blue.svg)
![tvOS](https://img.shields.io/badge/tvOS-13.0%2B-blue.svg)
![watchOS](https://img.shields.io/badge/watchOS-6.0%2B-blue.svg)
![visionOS](https://img.shields.io/badge/visionOS-1.0%2B-blue.svg)
```

**Build & CI:**
```markdown
![Build Status](https://github.com/mmj/cupertino/workflows/Build/badge.svg)
![SwiftLint](https://github.com/mmj/cupertino/workflows/SwiftLint/badge.svg)
```

**Release & License:**
```markdown
![Latest Release](https://img.shields.io/github/v/release/mmj/cupertino)
![License](https://img.shields.io/badge/License-MIT-green.svg)
```

**Project Stats:**
```markdown
![GitHub Stars](https://img.shields.io/github/stars/mmj/cupertino?style=social)
![Documentation](https://img.shields.io/badge/docs-13K%2B%20pages-success)
![Sample Code](https://img.shields.io/badge/samples-607%20projects-blue)
```

---

## GitHub Actions Workflows

### 1. Build & Test Workflow (`.github/workflows/build.yml`)

**Purpose:** Build project on every push/PR to ensure it compiles

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

### 2. SwiftLint Workflow (`.github/workflows/swiftlint.yml`)

**Purpose:** Enforce code quality on PRs

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

### 3. Daily Documentation Check (`.github/workflows/daily-check.yml`)

**Purpose:** Automatically check for documentation updates daily

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

### 4. Release Workflow (`.github/workflows/release.yml`)

**Purpose:** Automate releases when tags are pushed

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

## GitHub Repository Settings

### Required Secrets
None required for basic workflows. All use `GITHUB_TOKEN` which is automatically provided.

### Branch Protection Rules

For `main` branch:
- ✅ Require pull request reviews before merging
- ✅ Require status checks to pass:
  - Build
  - SwiftLint
- ✅ Require branches to be up to date before merging

---

## Automated Documentation Updates Strategy

### Option 1: Notification Only (Recommended)

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

### Option 2: Automated Update (Advanced)

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

## Project Statistics Badges

### Dynamic Badges (Updated by Scripts)

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

## Timeline

### Phase 7a: README Badges (Week 1)
1. Add Swift version badge
2. Add platform badges
3. Add license badge
4. Add project stats badges

### Phase 7b: GitHub Actions (Week 2)
1. Implement build workflow
2. Implement SwiftLint workflow
3. Test on PRs
4. Implement release workflow

### Phase 7c: Automated Checks (Week 3 - after Phase 5b)
1. Implement daily check workflow (requires Phase 5b fast check mode)
2. Test notification system
3. Document maintenance process

---

*Last updated: 2024-11-15*
*Status: Planning document for Phase 7 implementation*
