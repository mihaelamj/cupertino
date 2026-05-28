# --request-delay

Delay in seconds between crawler requests

## Synopsis

```bash
cupertino fetch --source apple-docs --request-delay <seconds>
```

## Description

Sets the crawler politeness delay used between fetched pages. The value is
passed through to `Shared.Configuration.Crawler.requestDelay`. Values must be
finite and greater than or equal to `0`.

Use a larger value for gentler crawls against remote documentation sites, or
`0` for controlled local/test crawls where no delay is needed.

## Default

`0.05`

## Example

```bash
# Wait 250ms between crawler requests
cupertino fetch --source apple-docs --request-delay 0.25
```

## Notes

- This option applies to standard `Shared.Configuration.Crawler` web crawls,
  such as `apple-docs` and `swift-org`.
- Package metadata and archive download stages have their own fetch behaviour
  and are not controlled by this option.
