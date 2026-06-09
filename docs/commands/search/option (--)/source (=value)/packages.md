# packages

Swift package metadata source

## Synopsis

```bash
cupertino search <query> --source packages
```

## Description

Filters search results to only include indexed Swift package source and documentation chunks from `packages.db`.

## Content

- **Package README and DocC content**
- **Package source-file chunks**
- **Repository URLs**
- **Stars and popularity metrics**
- **License information**
- **Deployment-target and Swift-tools annotations**

## Typical Size

- **185 curated packages** indexed in the v1.3.0 release bundle
- **Bundled by `cupertino setup`** (no crawl required for normal users)
- Updated periodically by maintainers

## Examples

### Search for Networking Packages
```bash
cupertino search "networking" --source packages
```

### Search for Database Packages
```bash
cupertino search "database" --source packages
```

### Search by Author
```bash
cupertino search "vapor" --source packages
```

## Read Identifiers

Results use package-relative identifiers, not a custom URI scheme:

```
<owner>/<repo>/<relative-path>
```

Search results include a `readFullCommand` such as:

```bash
cupertino read pointfreeco/swift-navigation/README.md --source packages
```

## How to Populate

The packages database is included in the release bundle downloaded by `cupertino setup`.
Maintainers can rebuild it from fetched package archives:

```bash
cupertino save --source packages
```

To fetch package source archives first:

```bash
# Fetch source archives for priority packages (#217). Post-#1108 stage 2
# is the default, so no flag is needed.
cupertino fetch --source packages

# Rebuild index
cupertino save --source packages
```

## Priority Packages

The release bundle indexes the curated package closure maintained by Cupertino,
including Apple packages and widely used ecosystem packages.

## Notes

- Bundled in `packages.db` by `cupertino setup`
- Full package chunks, not metadata-only search
- Updated periodically in Cupertino releases
- Great for discovering Swift packages
