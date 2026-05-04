# --print-unresolved

Print unresolved doc:// markers to stdout

## Synopsis

```bash
cupertino resolve-refs --input <path> --print-unresolved
```

## Description

After the harvest+rewrite (and optional `--use-network` / `--use-webview` passes), print the sorted, deduplicated list of `doc://...` markers that no source could resolve. Useful for triaging coverage gaps in the indexed corpus.

## Default

`false`

## Example

```bash
cupertino resolve-refs --input ~/.cupertino/docs --use-network --print-unresolved
```

## Output

```
doc://com.apple.documentation/foundation/url
doc://com.apple.documentation/swift/range
…
```

## Notes

- Output goes to stdout; pipe to a file for later analysis.
- Each marker appears once even if referenced from multiple pages.
- Combines with the rest of the flags — doesn't suppress the rewrite.
