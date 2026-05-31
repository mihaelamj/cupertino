# --pattern

Swift concurrency pattern to match. Required.

## Synopsis

```bash
cupertino search-concurrency --pattern <pattern>
```

## Description

Finds symbols that use the named concurrency construct.

## Values

`async`, `actor`, `sendable`, `mainactor`, `task`, `asyncsequence`.

## Default

None. This option is required.

## Example

```bash
cupertino search-concurrency --pattern actor
cupertino search-concurrency --pattern sendable --framework foundation
```
