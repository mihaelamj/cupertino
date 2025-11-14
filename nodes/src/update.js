import { crawl } from './crawler.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load configuration
const configPath = path.join(__dirname, '..', 'config.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

/**
 * Update script that performs incremental crawls
 * Only re-crawls pages that have changed since the last crawl
 */
async function update() {
  console.log('🔄 Starting incremental update...\n');

  // Load existing metadata
  const metadataPath = path.resolve(config.changeDetection.metadataFile);
  let metadata = null;

  try {
    if (fs.existsSync(metadataPath)) {
      metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
      console.log(`📋 Found existing metadata:`);
      console.log(`   Last crawl: ${metadata.lastCrawl}`);
      console.log(`   Total pages tracked: ${Object.keys(metadata.pages).length}`);
      console.log(`   Previous stats:`, metadata.stats);
      console.log();
    } else {
      console.log('📋 No existing metadata found. This will be a full crawl.\n');
    }
  } catch (err) {
    console.warn('⚠️  Could not load metadata:', err.message);
    console.log('   Proceeding with full crawl...\n');
  }

  // Perform the crawl
  const stats = await crawl();

  // Display update summary
  console.log('\n' + '='.repeat(60));
  console.log('📊 Update Summary');
  console.log('='.repeat(60));

  if (metadata && metadata.stats) {
    const previous = metadata.stats.totalPages || 0;
    const current = stats.totalPages;
    const diff = current - previous;

    console.log(`Previous crawl: ${previous} pages`);
    console.log(`Current crawl: ${current} pages`);
    console.log(`Difference: ${diff > 0 ? '+' : ''}${diff} pages`);
    console.log();
  }

  console.log(`New pages: ${stats.newPages}`);
  console.log(`Updated pages: ${stats.updatedPages}`);
  console.log(`Unchanged pages: ${stats.skippedPages}`);
  console.log(`Errors: ${stats.errors}`);
  console.log('='.repeat(60));

  // Check if we should merge PDFs
  if (config.pdfMerge.enabled && (stats.newPages > 0 || stats.updatedPages > 0)) {
    console.log('\n📚 PDF merge is enabled. Run `npm run merge` to combine PDFs by framework.');
  }

  return stats;
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  update().catch(err => {
    console.error('Fatal error during update:', err);
    process.exit(1);
  });
}

export { update };
