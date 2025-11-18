# Cupertino Bugs

Known issues and bugs that need to be fixed.

## Bug Fixes

### ✅ 1. Index command --clear flag validation error (FIXED)
- Fixed `--clear` flag default value (was `true`, now `false`)
- Resolves ArgumentParser validation error: "Boolean flags with initial value of `true` result in flag always being `true`"

**Status**: Fixed
**Priority**: Medium
**Component**: Index command
**Affected Command**: `cupertino index --clear`

## Open Bugs

### 1. fetch authenticate does not work
- it never opens the safari browser, I opened it manually
- investigate how other terminal commands are doing it
- maybe search GitHub for code examples

**Status**: Open
**Priority**: High
**Component**: Fetch command authentication
**Affected Command**: `cupertino fetch --type code --authenticate`
