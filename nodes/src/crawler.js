import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load configuration
const configPath = path.join(__dirname, '..', 'config.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

// ---------- STATE MANAGEMENT ----------

class CrawlerState {
  constructor() {
    this.metadataPath = path.resolve(config.changeDetection.metadataFile);
    this.metadata = this.loadMetadata();
  }

  loadMetadata() {
    try {
      if (fs.existsSync(this.metadataPath)) {
        return JSON.parse(fs.readFileSync(this.metadataPath, 'utf8'));
      }
    } catch (err) {
      console.warn('⚠️  Failed to load metadata, starting fresh:', err.message);
    }
    return {
      pages: {},
      lastCrawl: null,
      stats: {
        totalPages: 0,
        lastUpdated: null
      }
    };
  }

  saveMetadata() {
    const dir = path.dirname(this.metadataPath);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(this.metadataPath, JSON.stringify(this.metadata, null, 2));
  }

  shouldRecrawl(url, contentHash) {
    if (config.changeDetection.forceRecrawl) return true;
    if (!config.changeDetection.enabled) return true;

    const pageData = this.metadata.pages[url];
    if (!pageData) return true;

    // Check if content hash changed
    if (pageData.contentHash !== contentHash) return true;

    // Check if file still exists
    if (!fs.existsSync(pageData.pdfPath)) return true;

    return false;
  }

  updatePage(url, data) {
    this.metadata.pages[url] = {
      ...data,
      lastCrawled: new Date().toISOString()
    };
  }

  finalizeCrawl(stats) {
    this.metadata.lastCrawl = new Date().toISOString();
    this.metadata.stats = stats;
    this.saveMetadata();
  }
}

// ---------- HELPERS ----------

function normalizeUrl(raw) {
  const u = new URL(raw);
  u.hash = '';
  u.search = '';
  return u.toString();
}

function filenameFor(urlStr) {
  const cleaned = urlStr
    .replace('https://developer.apple.com/', '')
    .toLowerCase()  // Convert to lowercase for case-insensitive handling
    .replace(/[^a-z0-9._-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '');
  return cleaned.length ? cleaned : 'index';
}

function frameworkFor(urlStr) {
  const parts = urlStr.split('/');
  const idx = parts.indexOf('documentation');
  // Convert to lowercase for case-insensitive framework folders
  return (idx >= 0 && parts[idx + 1]) ? parts[idx + 1].toLowerCase() : 'root';
}

function shouldVisit(url, visited) {
  if (!url.startsWith('https://developer.apple.com/documentation/')) {
    return false;
  }

  if (!config.crawler.allowedPrefixes.some(prefix => url.startsWith(prefix))) {
    return false;
  }

  const normalized = normalizeUrl(url);
  if (visited.has(normalized)) return false;

  return true;
}

async function getPageContentHash(page) {
  try {
    // Get text content of main documentation area
    const content = await page.evaluate(() => {
      const main = document.querySelector('main') || document.body;
      return main.innerText;
    });
    return crypto.createHash('sha256').update(content).digest('hex');
  } catch (err) {
    return null;
  }
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function retryOperation(operation, attempts = config.crawler.retryAttempts) {
  for (let i = 0; i < attempts; i++) {
    try {
      return await operation();
    } catch (err) {
      if (i === attempts - 1) throw err;
      console.log(`   ⚠️  Attempt ${i + 1} failed, retrying in ${config.crawler.retryDelay}ms...`);
      await delay(config.crawler.retryDelay);
    }
  }
}

// ---------- LOGGING ----------

class Logger {
  constructor() {
    this.logFile = path.resolve(config.logging.logFile);
    const dir = path.dirname(this.logFile);
    fs.mkdirSync(dir, { recursive: true });
  }

  log(message, level = 'INFO') {
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] [${level}] ${message}\n`;

    if (config.logging.verbose) {
      console.log(message);
    }

    fs.appendFileSync(this.logFile, logMessage);
  }

  error(message, err) {
    this.log(`${message}: ${err.message}`, 'ERROR');
  }
}

// ---------- MAIN CRAWLER ----------

export async function crawl(options = {}) {
  const state = new CrawlerState();
  const logger = new Logger();
  const outputDir = path.resolve(config.crawler.outputDir);

  fs.mkdirSync(outputDir, { recursive: true });

  const queue = [{
    url: options.startUrl || config.crawler.startUrl,
    depth: 0
  }];
  const visited = new Set();

  let stats = {
    totalPages: 0,
    newPages: 0,
    updatedPages: 0,
    skippedPages: 0,
    errors: 0,
    startTime: new Date().toISOString()
  };

  logger.log('🚀 Starting Apple Documentation Crawler');
  logger.log(`Output directory: ${outputDir}`);
  logger.log(`Change detection: ${config.changeDetection.enabled ? 'enabled' : 'disabled'}`);

  const browser = await chromium.launch({
    headless: true
  });

  const page = await browser.newPage({
    viewport: config.crawler.viewport
  });

  while (queue.length > 0 && visited.size < config.crawler.maxPages) {
    const { url, depth } = queue.shift();
    const normalized = normalizeUrl(url);

    if (visited.has(normalized)) continue;
    visited.add(normalized);

    const framework = frameworkFor(normalized);
    const frameworkDir = path.join(outputDir, framework);
    fs.mkdirSync(frameworkDir, { recursive: true });

    logger.log(`📄 [${visited.size}/${config.crawler.maxPages}] depth=${depth} [${framework}] ${normalized}`);

    try {
      // Load page with retry
      await retryOperation(async () => {
        await page.goto(normalized, {
          waitUntil: 'networkidle',
          timeout: 30000
        });
      });

      // Add delay to be respectful to the server
      await delay(config.crawler.requestDelay);

      // Get content hash for change detection
      const contentHash = await getPageContentHash(page);

      const baseName = filenameFor(normalized);
      const pdfPath = path.join(frameworkDir, `${baseName}.pdf`);

      // Check if we need to recrawl
      if (!state.shouldRecrawl(normalized, contentHash)) {
        logger.log(`   ⏩ No changes detected, skipping`);
        stats.skippedPages++;
      } else {
        // Save as PDF
        const isNew = !fs.existsSync(pdfPath);

        await retryOperation(async () => {
          await page.pdf({
            path: pdfPath,
            ...config.crawler.pdfOptions
          });
        });

        if (isNew) {
          stats.newPages++;
          logger.log(`   ✅ Saved new page: ${pdfPath}`);
        } else {
          stats.updatedPages++;
          logger.log(`   ♻️  Updated page: ${pdfPath}`);
        }

        // Update metadata
        state.updatePage(normalized, {
          url: normalized,
          framework,
          pdfPath,
          contentHash,
          depth
        });
      }

      stats.totalPages++;

      // Extract links
      const links = await page.$$eval('a[href]', anchors =>
        anchors
          .map(a => a.getAttribute('href') || '')
          .filter(href => href.startsWith('/documentation/'))
          .map(href => new URL(href, 'https://developer.apple.com').toString())
      );

      // Enqueue new links
      if (depth < config.crawler.maxDepth) {
        for (const link of links) {
          if (shouldVisit(link, visited)) {
            queue.push({ url: link, depth: depth + 1 });
          }
        }
      }

    } catch (err) {
      stats.errors++;
      logger.error(`   ❌ Error processing ${normalized}`, err);
    }
  }

  await browser.close();

  stats.endTime = new Date().toISOString();
  stats.duration = new Date(stats.endTime) - new Date(stats.startTime);

  state.finalizeCrawl(stats);

  logger.log('\n✅ Crawl completed!');
  logger.log(`📊 Statistics:`);
  logger.log(`   Total pages processed: ${stats.totalPages}`);
  logger.log(`   New pages: ${stats.newPages}`);
  logger.log(`   Updated pages: ${stats.updatedPages}`);
  logger.log(`   Skipped (unchanged): ${stats.skippedPages}`);
  logger.log(`   Errors: ${stats.errors}`);
  logger.log(`   Duration: ${Math.round(stats.duration / 1000)}s`);
  logger.log(`\n📁 PDFs saved to: ${outputDir}`);

  return stats;
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  crawl().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
}
