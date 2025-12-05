# --dry-run

Create zip locally without uploading.

## Synopsis

```bash
cupertino release --dry-run
```

## Description

Creates the zip file and calculates SHA256 checksum, but does not upload to GitHub. Useful for testing the release process or inspecting the output.

The zip file will be saved to the base directory (e.g., `~/.cupertino/cupertino-databases-v0.3.0.zip`).

## Examples

```bash
# Test release process
cupertino release --dry-run

# Inspect the zip file
unzip -l ~/.cupertino/cupertino-databases-v0.3.0.zip
```

## Default

`false` - Upload to GitHub
