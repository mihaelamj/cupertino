# AppleCupertino - Update & Refresh Strategy

## Current Capabilities (Already Implemented)

### ✅ Basic Update/Refresh
**Command:** `cupertino update`

**How it works:**
- Uses change detection with SHA256 content hashing
- Compares new content hash with stored hash
- Skips unchanged pages automatically
- Downloads only new or modified pages

**Statistics tracked:**
- `newPages` - newly discovered pages
- `updatedPages` - pages with changed content
- `skippedPages` - pages unchanged since last crawl

**Usage:**
```bash
# Incremental update (respects delays, downloads changes)
cupertino update --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

---

## Future Enhancement: Fast Check Mode (Phase 5b)

### Problem
Current update workflow:
1. Crawls all pages with request delays (~0.5s per page)
2. Downloads full HTML to check if changed
3. For 13,000 pages: ~2-3 hours just to check what changed

### Solution: Fast Check Mode

**Goal:** Quickly discover what changed without downloading everything

**Command:** `cupertino check` (to be implemented)

**How it will work:**
```bash
# 1. Fast check (no delays, just discover changes)
cupertino check \
  --output changes.json \
  --no-delay

# Output: changes.json
{
  "checked_at": "2024-11-20T10:00:00Z",
  "total_checked": 13000,
  "new": [
    "https://developer.apple.com/documentation/swiftui/new-api"
  ],
  "modified": [
    "https://developer.apple.com/documentation/swift/array"
  ],
  "removed": [
    "https://developer.apple.com/documentation/deprecated-api"
  ],
  "unchanged": 12995
}

# 2. Review changes
cat changes.json

# 3. Selective download (only changed pages, with delays)
cupertino update --only-changed changes.json

# OR: Full update with all changes
cupertino update
```

### Fast Check Implementation Strategy

**Phase 1: Lightweight Checks**
- Skip request delays entirely
- Only fetch HTTP headers (HEAD request) or minimal metadata
- Compare Last-Modified headers with stored timestamps
- Or fetch minimal HTML to compute hash quickly

**Phase 2: Parallel Checking**
- Check multiple URLs concurrently (e.g., 10-20 at once)
- Much faster than sequential crawling
- Generate change list in minutes instead of hours

**Phase 3: Smart Filtering**
- Only check pages we've seen before
- New pages discovered during actual update
- Removed pages detected by 404 responses

### Expected Performance

**Current update (with downloads):**
- 13,000 pages × 0.5s delay = ~2 hours minimum
- Plus download/processing time = ~3-4 hours total

**Fast check mode:**
- 13,000 pages ÷ 20 concurrent = 650 batches
- 650 batches × 0.1s = ~65 seconds
- Plus processing = **~2-5 minutes total**

**Improvement:** 95%+ faster for discovering changes

---

## Crawl Metadata Storage

### Current Crawl Session (Nov 14-15, 2024)
- Started: Nov 14, 2024 00:00:00
- Expected completion: Nov 15, 2024 22:00:00
- Duration: ~22 hours
- Pages: ~13,000 (10,099+ so far)
- **This is a one-time full crawl** - future updates will be incremental only

### Future Index Schema

Add to `search.db`:

```sql
CREATE TABLE crawl_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT NOT NULL,           -- ISO 8601 timestamp
    completed_at TEXT,                   -- ISO 8601 timestamp
    total_pages INTEGER,
    frameworks_covered TEXT,             -- JSON array
    version TEXT,                        -- e.g., "2024-11-15"
    snapshot_id TEXT UNIQUE              -- e.g., "snapshot-2024-11-15"
);

CREATE TABLE crawl_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    crawl_id INTEGER REFERENCES crawl_metadata(id),
    url TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    last_modified TEXT,
    status TEXT,                         -- "new", "modified", "unchanged"
    crawled_at TEXT NOT NULL
);
```

**Benefits:**
- Track when each crawl happened
- Compare snapshots over time
- Know exact dates for "What changed since X?"
- Historical analysis of documentation evolution

---

## Update Workflows

### Workflow 1: Daily Quick Check (Recommended)

```bash
# Run daily (fast, no downloads)
cupertino check --output /tmp/daily-check.json

# If changes found:
if [ $(jq '.new | length' /tmp/daily-check.json) -gt 0 ]; then
  echo "Changes detected, running update..."
  cupertino update --only-changed /tmp/daily-check.json
fi
```

### Workflow 2: Weekly Full Update

```bash
# Full incremental update (downloads all changes)
cupertino update

# Create snapshot
cupertino build-index --create-snapshot
```

### Workflow 3: Periodic Full Refresh (When Needed)

**Note:** Full re-crawls are time-intensive (22+ hours). Current crawl started Nov 14, finishes Nov 15.

```bash
# Force re-crawl everything (ignore change detection)
# ⚠️ WARNING: Takes 22+ hours for ~13K pages
cupertino --force \
  --start-url https://developer.apple.com/documentation/swift \
  --output-dir /Volumes/Code/DeveloperExt/appledocsucker/docs
```

**Recommendation:** Use fast check + selective update instead of full re-crawls

---

## MCP Integration

### Future Tools

**1. `get_latest_changes`**
```json
{
  "tool": "get_latest_changes",
  "parameters": {
    "framework": "SwiftUI",
    "since": "2024-11-01"
  }
}
```

**2. `check_for_updates`**
```json
{
  "tool": "check_for_updates",
  "parameters": {
    "quick": true
  }
}
```

Returns: Summary of what changed since last crawl

**3. `get_crawl_info`**
```json
{
  "tool": "get_crawl_info"
}
```

Returns:
```json
{
  "last_crawl": "2024-11-15T22:00:00Z",
  "total_pages": 13000,
  "next_check_recommended": "2024-11-22T22:00:00Z"
}
```

---

## Implementation Priority

### Phase 5a: Snapshot Infrastructure (2-3 hours)
1. Add `crawl_metadata` table to `search.db`
2. Store crawl dates during indexing
3. Create snapshot IDs (e.g., "snapshot-2024-11-15")

### Phase 5b: Fast Check Mode (2-3 hours)
1. Implement `cupertino check` command
2. Skip delays when checking only
3. Parallel HEAD requests or lightweight fetches
4. Generate changes.json output

### Phase 5c: Selective Update (1-2 hours)
1. Add `--only-changed` flag to update command
2. Read changes.json
3. Download only URLs in "new" or "modified" lists

### Phase 5d: Historical Tracking (1-2 hours)
1. `crawl_history` table implementation
2. `cupertino compare` command
3. Compare two snapshots
4. Generate delta reports

---

## Benefits Summary

### For Users
- ✅ Know immediately if documentation updated (2-5 min check vs 3-4 hour crawl)
- ✅ Download only what changed (save time and bandwidth)
- ✅ Historical tracking ("What changed this month?")
- ✅ Automated daily checks (cron job)

### For AI Agents
- ✅ Query: "What's new in SwiftUI?"
- ✅ Query: "Show me APIs modified in last week"
- ✅ Always up-to-date documentation
- ✅ Know when docs were last refreshed

---

## Example Cron Job

```bash
#!/bin/bash
# ~/.docsucker/daily-check.sh

# Fast check for changes
cupertino check --output /tmp/docsucker-check.json --no-delay

# Count changes
NEW=$(jq '.new | length' /tmp/docsucker-check.json)
MODIFIED=$(jq '.modified | length' /tmp/docsucker-check.json)

# If significant changes, update
if [ $((NEW + MODIFIED)) -gt 10 ]; then
  echo "$(date): $NEW new, $MODIFIED modified - running update"
  cupertino update --only-changed /tmp/docsucker-check.json
  cupertino build-index
else
  echo "$(date): No significant changes ($NEW new, $MODIFIED modified)"
fi
```

Add to crontab:
```
# Check daily at 2 AM
0 2 * * * /Users/mmj/.docsucker/daily-check.sh >> /Users/mmj/.docsucker/update.log 2>&1
```

---

*Last updated: 2024-11-15*
*Status: Planning document for Phase 5 implementation*
