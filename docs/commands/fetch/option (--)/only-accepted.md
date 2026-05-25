# --only-accepted / --no-only-accepted

Filter Swift Evolution proposals to accepted/implemented only

## Synopsis

```bash
cupertino fetch --source swift-evolution --only-accepted
cupertino fetch --source swift-evolution --no-only-accepted
```

## Description

When fetching `--source swift-evolution`, only accepted/implemented proposals are downloaded by default. Pass `--no-only-accepted` to also download in-flight, returned-for-revision, withdrawn, etc.

## Default

`true` (only accepted)

## Example

```bash
# Default: accepted/implemented proposals only
cupertino fetch --source swift-evolution

# All proposals regardless of status
cupertino fetch --source swift-evolution --no-only-accepted
```

## Notes

- Status is parsed from the proposal's frontmatter via regex; both SE-prefixed and ST-prefixed (Swift Testing) proposals work.
- The default makes search ranking better — withdrawn / returned-for-revision proposals create noise.
