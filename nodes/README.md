# Apple Documentation Crawler 2.0

An enhanced web crawler for Apple's official documentation that automatically downloads pages as PDFs, detects changes, and schedules regular updates.

## Features

- **Smart Change Detection**: Only re-crawls pages that have been updated
- **Automated Scheduling**: Set up regular crawls with cron expressions
- **PDF Generation**: Converts documentation pages to searchable PDFs
- **Framework Organization**: Automatically organizes docs by framework
- **PDF Merging**: Combines individual PDFs into complete framework books
- **Case-Insensitive**: Handles capitalization variations (e.g., "Accelerate" vs "accelerate")
- **Incremental Updates**: Efficient updates that skip unchanged content
- **Retry Logic**: Automatic retries with configurable delays
- **Detailed Logging**: Track crawl progress and statistics

## Installation

1. Install dependencies:
```bash
npm install
```

2. Install Playwright browsers:
```bash
npx playwright install chromium
```

## Usage

### Initial Crawl

Run a complete crawl of Apple documentation:

```bash
npm run crawl
```

This will:
- Crawl all Apple documentation starting from the configured URL
- Save each page as a PDF organized by framework
- Track metadata for future incremental updates
- Generate a log file with detailed progress

### Incremental Updates

Update only changed or new pages:

```bash
npm run update
```

This will:
- Check existing pages for changes using content hashing
- Only re-download pages that have been modified
- Add newly discovered pages
- Skip unchanged pages for efficiency

### Scheduled Updates

Run the crawler on a regular schedule:

```bash
npm run schedule
```

This starts a background scheduler that will automatically run updates based on your cron configuration.

### Merge PDFs

Combine individual PDFs by framework:

```bash
npm run merge
```

This creates:
- One merged PDF per framework (e.g., `swiftui_FULL.pdf`)
- Table of contents files (e.g., `swiftui_TOC.txt`)
- Organized output in the `docs/merged` directory

## Configuration

Edit `config.json` to customize behavior:

### Crawler Settings

```json
{
  "crawler": {
    "startUrl": "https://developer.apple.com/documentation/",
    "maxPages": 5000,
    "maxDepth": 15,
    "outputDir": "./docs",
    "requestDelay": 500,
    "retryAttempts": 3
  }
}
```

- `startUrl`: Where to begin crawling
- `maxPages`: Maximum number of pages to crawl
- `maxDepth`: Maximum link depth from start URL
- `outputDir`: Where to save PDFs
- `requestDelay`: Milliseconds to wait between requests (be respectful!)
- `retryAttempts`: Number of retries for failed requests

### Change Detection

```json
{
  "changeDetection": {
    "enabled": true,
    "metadataFile": "./docs/.metadata.json",
    "forceRecrawl": false
  }
}
```

- `enabled`: Enable smart change detection
- `metadataFile`: Where to store page metadata
- `forceRecrawl`: Set to `true` to re-download everything

### Scheduling

```json
{
  "scheduling": {
    "enabled": false,
    "cronExpression": "0 2 * * *",
    "timezone": "America/Los_Angeles"
  }
}
```

- `enabled`: Enable automatic scheduled updates
- `cronExpression`: When to run (uses cron syntax)
- `timezone`: Timezone for schedule

**Common Cron Expressions:**
- `0 2 * * *` - Every day at 2:00 AM
- `0 */6 * * *` - Every 6 hours
- `0 0 * * 0` - Every Sunday at midnight
- `0 0 1 * *` - First day of every month

### PDF Options

```json
{
  "pdfOptions": {
    "format": "A4",
    "printBackground": true,
    "margin": {
      "top": "20px",
      "right": "20px",
      "bottom": "20px",
      "left": "20px"
    }
  }
}
```

## Project Structure

```
apple_docs_crawl/
├── config.json           # Configuration file
├── package.json          # Dependencies and scripts
├── src/
│   ├── crawler.js        # Main crawler with change detection
│   ├── update.js         # Incremental update script
│   ├── scheduler.js      # Cron-based scheduler
│   └── merge-pdfs.js     # PDF merging utility
└── docs/                 # Output directory
    ├── .metadata.json    # Crawl metadata (auto-generated)
    ├── crawler.log       # Detailed logs
    ├── swiftui/          # Framework-specific PDFs
    ├── uikit/
    ├── ...
    └── merged/           # Merged framework books
        ├── swiftui_FULL.pdf
        ├── swiftui_TOC.txt
        └── ...
```

## How It Works

### 1. Initial Crawl
- Starts from the configured URL
- Uses BFS (breadth-first search) to discover pages
- Converts each page to PDF using Playwright
- Organizes by framework (extracted from URL)
- Stores metadata (URL, content hash, timestamp)

### 2. Change Detection
- Computes SHA-256 hash of page content
- Compares with stored hash from previous crawl
- Only re-downloads if hash differs or file is missing
- Dramatically speeds up subsequent crawls

### 3. Case-Insensitive Handling
- All filenames and folder names converted to lowercase
- Prevents duplicates like "Accelerate" and "accelerate"
- Maintains consistent organization

### 4. PDF Merging
- Combines individual PDFs per framework
- Generates table of contents
- Preserves page order
- Creates single reference document per framework

## Tips

### Crawling Specific Frameworks

To crawl only specific frameworks, modify `allowedPrefixes` in config.json:

```json
{
  "allowedPrefixes": [
    "https://developer.apple.com/documentation/swiftui",
    "https://developer.apple.com/documentation/uikit"
  ]
}
```

### Monitoring Progress

Watch the log file in real-time:

```bash
tail -f docs/crawler.log
```

### Disk Space

Apple's documentation is extensive. Expect:
- Full crawl: 10-50 GB depending on `maxPages`
- Incremental updates: Minimal additional space
- Merged PDFs: Additional 20-30% of individual PDFs

### Performance

Adjust these settings based on your needs:

**Faster crawling** (less respectful):
```json
{
  "requestDelay": 100,
  "maxPages": 10000
}
```

**Slower, more respectful** (recommended):
```json
{
  "requestDelay": 1000,
  "maxPages": 5000
}
```

## Troubleshooting

### "Too many open files" error

Increase file descriptor limit:
```bash
ulimit -n 4096
```

### Playwright browser issues

Reinstall browsers:
```bash
npx playwright install --force chromium
```

### Out of memory

Reduce `maxPages` or run in smaller batches:
```json
{
  "maxPages": 1000
}
```

### Stuck/frozen crawl

The crawler respects `networkidle` and will wait for pages to fully load. Some pages may take longer. Check the log file to see which page is being processed.

## Development

### Run with verbose logging

Logging is controlled in `config.json`:
```json
{
  "logging": {
    "verbose": true,
    "logFile": "./docs/crawler.log"
  }
}
```

### Force complete re-crawl

Set in `config.json`:
```json
{
  "changeDetection": {
    "forceRecrawl": true
  }
}
```

Or delete the metadata file:
```bash
rm docs/.metadata.json
```

## License

This crawler is for personal documentation purposes. Please respect Apple's terms of service and robots.txt when crawling their documentation.

## Credits

Enhanced version based on the original Apple docs crawler, now with:
- Automated change detection
- Scheduled updates
- Better error handling
- Incremental crawling
- Modern Node.js architecture
