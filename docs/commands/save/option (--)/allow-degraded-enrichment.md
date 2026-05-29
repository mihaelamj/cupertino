# --allow-degraded-enrichment

Allow the save to proceed when a selected source is missing a declared enrichment input, at reduced coverage.

## Synopsis

```bash
cupertino save --source <id> --allow-degraded-enrichment
```

## Description

Each source declares the enrichment input files it needs (`Search.SourceDefinition.requiredEnrichmentInputs`): apple-docs, samples, and packages need `apple-constraints.json` in the base directory; packages also needs a per-package `availability.json`. Before any indexing, a single generic preflight checks those inputs for the selected sources and **hard-fails** when one is missing, so a multi-hour save cannot silently finish at degraded coverage.

This flag downgrades that hard-fail to a warning and proceeds:

- Without `apple-constraints.json`, the constraints enrichment pass runs at iter-1+2 coverage (~16% of `doc_symbols`) instead of iter-3 (~38%), a real search-quality regression.
- Without per-package `availability.json`, packages fall back to the `Package.swift` deployment floor only (no `@available` platform floors), and `swift_tools_version` degrades.

Set it only when you know you do not need the authoritative Apple-SDK constraints or package availability: testing a non-docs source, a smoke save against a tiny fixture, or a fresh dev install before `cupertino-constraints-gen` (for `apple-constraints.json`) or `cupertino fetch --source packages --annotate-availability` (for the sidecars) has run.

## Default

`false`. Missing enrichment inputs are a hard error; you must opt in to degrade.

## Example

```bash
# Smoke-save apple-docs from a fixture that has no constraints table
cupertino save --source apple-docs --docs-dir ./fixture --allow-degraded-enrichment
```
