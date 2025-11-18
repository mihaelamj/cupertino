# cupertino fetch

Fetch resources without web crawling

## Synopsis

```bash
cupertino fetch --type <type> [options]
```

## Description

The `fetch` command downloads resources directly without using WKWebView crawling. This is faster and more efficient for bulk downloads of known resources like Swift packages or Apple sample code.

## Options

- [--type](type/) - Type of resource to fetch (packages, code) **[REQUIRED]**
- [--output-dir](output-dir.md) - Output directory for downloaded resources
- [--limit](limit.md) - Maximum number of items to fetch
- [--force](force.md) - Force re-download of existing files
- [--resume](resume.md) - Resume from checkpoint if interrupted
- [--authenticate](authenticate.md) - Launch visible browser for authentication (code only)

## Examples

### Fetch All Swift Packages
```bash
cupertino fetch --type packages
```

### Fetch Apple Sample Code (with Authentication)
```bash
cupertino fetch --type code --authenticate
```

### Fetch Limited Number of Packages
```bash
cupertino fetch --type packages --limit 50 --output-dir ./my-packages
```

### Resume Interrupted Fetch
```bash
cupertino fetch --type packages --resume
```

## Output

### Swift Packages
- **checkpoint.json** - Progress tracking with package metadata
- **Package metadata** - JSON files with GitHub information

### Apple Sample Code
- **ZIP files** - Downloaded sample code projects
- **checkpoint.json** - Progress tracking

## Notes

- **Packages**: Fetches from Swift Package Index API + GitHub API
- **Sample Code**: Requires authentication with Apple ID
- Both types support resume capability via checkpoints
- Change detection prevents re-downloading unchanged resources
