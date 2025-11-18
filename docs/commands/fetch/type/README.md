# --type

Type of resource to fetch **[REQUIRED]**

## Synopsis

```bash
cupertino fetch --type <value>
```

## Description

Specifies which type of resource to fetch. This option is required for the fetch command.

## Available Types

- [packages](packages.md) - Swift packages from Swift Package Index
- [code](code.md) - Apple sample code projects

## Quick Examples

```bash
# Fetch Swift Packages
cupertino fetch --type packages

# Fetch Apple Sample Code (requires auth)
cupertino fetch --type code --authenticate
```

## Comparison

| Type | Source | Output | Authentication |
|------|--------|--------|----------------|
| `packages` | Swift Package Index + GitHub | JSON metadata | Not required |
| `code` | Apple Developer | ZIP files | Required |

## Notes

- This option is **required** for fetch command
- Each type has different output format
- Sample code requires `--authenticate` flag
