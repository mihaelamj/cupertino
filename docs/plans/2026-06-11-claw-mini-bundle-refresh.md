# Claw Mini Bundle Refresh Automation (Issue #1274)

Goal: Automate periodic (weekly) database bundle refreshes by utilizing the Claw Mini (`claw`) as the primary crawler and build worker, bypassing public cloud CI blockers.

---

## 1. Context & Blocker Analysis

A pure GitHub-hosted Actions workflow running on standard GHA runners is blocked by the following:
1. **CDN/Akamai IP Firewall**: Apple's documentation CDN blocks public cloud IP ranges. Standard GHA runners cannot crawl developer.apple.com directly without paid residential proxy networks.
2. **Xcode SDK Dependency**: Post-indexing passes like [AppleConstraintsPass](file:///Volumes/Code/DeveloperExt/public/cupertino/Packages/Sources/AppleConstraintsPass/Enrichment.AppleConstraintsPass.swift#L16) and [AppleConformancesPass](file:///Volumes/Code/DeveloperExt/public/cupertino/Packages/Sources/AppleConstraintsPass/Enrichment.AppleConformancesPass.swift#L12) require `apple-constraints.json` and `apple-conformances.json`. These must be compiled from Xcode SDK symbol graphs using `swift symbolgraph-extract`. Hosted Linux/macOS runners cannot dynamically extract these across all platforms (iOS, watchOS, tvOS, visionOS) in a timely or cost-effective manner.
3. **High Resource Footprint**: Running a full crawl and compilation requires over 5 GB of disk space and hours of CPU time, exceeding GHA resource limits and timeouts.

---

## 2. Proposed Architecture (Claw Mini Worker)

The Claw Mini (`claw-mihaljevic.local` / `claw`) serves as the dedicated mesh worker. Since it runs on a residential/office network and has a full Xcode installation, it naturally bypasses the CDN and SDK blockers.

```
Studio/Work Mac (Controller)          Claw Mini (Worker)
────────────────────────────          ──────────────────
 1. Trigger cron/LaunchAgent  ────>    2. git pull & swift build
                                       3. cupertino fetch --source all
                                       4. cupertino-constraints-gen
                                       5. cupertino save --all --clear
                                       6. cupertino-rel databases --tag vX.Y.Z
                                                │
                                                ▼
                                       7. Uploads to GitHub Releases
```

### 2.1 Refresher Pipeline (`launchagents/cupertino-release-refresher.sh`)
The automation script will reside in the private `mihaela-automate` repository and execute these steps:

1. **Self-Update**: Pulls the latest changes from `mihaelamj/cupertino` onto Claw.
2. **Compile Binary**: Runs `swift build -c release` inside the `Packages/` directory to ensure we run the latest compiler and indexing logic.
3. **Incremental Fetch**: Runs `cupertino fetch --source all` (resuming from local snapshots) to fetch the documentation and package deltas.
4. **Update Lookups**: Runs `cupertino-constraints-gen` and `cupertino-constraints-gen conformances` to extract constraints and conformances from Claw's local Xcode SDKs.
5. **Re-Index Databases**: Runs `cupertino save --all --clear` to build the new SQLite databases from scratch, running the offline post-indexing enrichment passes.
6. **Integrity Validation**: Runs `cupertino doctor --save` to verify the output.
7. **Release Promotion**: Runs `cupertino-rel databases --tag <version> --repo mihaelamj/cupertino-docs` to zip the output DBs and push them directly to GitHub Releases.

---

## 3. Automation Setup (Launchd Agent)

A persistent LaunchAgent `com.mihaela.cupertino-release-refresher` will be installed on the Claw Mini to execute the refresher script on a weekly schedule (e.g. every Monday at 02:00 UTC).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mihaela.cupertino-release-refresher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Volumes/ClawSSD/Developer/personal/private/mihaela-automate/launchagents/cupertino-release-refresher.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
        <key>Weekday</key>
        <integer>1</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/Users/a1/Library/Logs/cupertino-release-refresher.out</string>
    <key>StandardErrorPath</key>
    <string>/Users/a1/Library/Logs/cupertino-release-refresher.err</string>
</dict>
</plist>
```

---

## 4. Implementation Steps

1. **Write the Refresher Script**: 
   Create `launchagents/cupertino-release-refresher.sh` in the `mihaela-automate` repository.
2. **Create the Installer**: 
   Create `launchagents/install-cupertino-release-refresher.sh` mirroring the helper installation logic from the existing `install-cupertino-crawl-claw.sh`.
3. **Configure Git Credentials**:
   Ensure `a1`'s user environment on `claw` has `GITHUB_TOKEN` set up in `~/.zshrc` (or similar) with write access to `mihaelamj/cupertino-docs`.
4. **Deploy and Test**:
   SSH into `claw` and bootstrap the LaunchAgent. Trigger a dry-run release to verify.

---

## 5. Open Questions & Versioning

* **Version Bump Automation**: How should the script determine the next version number?
  * *Option A*: Read the current version, bump the patch (e.g., `v1.3.1` -> `v1.3.2`), update `Shared.Constants.App.version`, and commit the version change to `develop`.
  * *Option B*: Publish under a rolling tag like `bundle-latest` or `nightly`. This requires adding support for rolling tags in `cupertino setup`.
