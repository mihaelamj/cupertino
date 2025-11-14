import { PDFDocument } from 'pdf-lib';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load configuration
const configPath = path.join(__dirname, '..', 'config.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

/**
 * Merges individual PDFs per framework into a single book
 * Similar to the original build_framework_books.sh but in Node.js
 */

async function mergeFrameworkPDFs(frameworkName, frameworkPath, outputDir) {
  console.log(`\n📚 Processing ${frameworkName}...`);

  // Find all PDF files in the framework directory
  const files = fs.readdirSync(frameworkPath)
    .filter(f => f.endsWith('.pdf'))
    .sort()
    .map(f => path.join(frameworkPath, f));

  if (files.length === 0) {
    console.log(`   ℹ️  No PDFs found, skipping`);
    return null;
  }

  console.log(`   Found ${files.length} PDFs`);

  // Create a new merged PDF document
  const mergedPdf = await PDFDocument.create();

  // Track page numbers for TOC
  const tocEntries = [];
  let currentPage = 1;

  // Merge each PDF
  for (const filePath of files) {
    try {
      const pdfBytes = fs.readFileSync(filePath);
      const pdf = await PDFDocument.load(pdfBytes);
      const pages = await mergedPdf.copyPages(pdf, pdf.getPageIndices());

      const fileName = path.basename(filePath, '.pdf');
      // Clean up the title: remove framework prefix and convert underscores to spaces
      let title = fileName
        .replace(new RegExp(`^documentation_${frameworkName}_`, 'i'), '')
        .replace(new RegExp(`^${frameworkName}_`, 'i'), '')
        .replace(/_/g, ' ');

      // Capitalize first letter of each word for better readability
      title = title.split(' ')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' ');

      tocEntries.push({
        title,
        pageNumber: currentPage,
        pageCount: pages.length
      });

      pages.forEach(page => mergedPdf.addPage(page));
      currentPage += pages.length;

      console.log(`   ✓ Added: ${title} (${pages.length} pages)`);
    } catch (err) {
      console.error(`   ✗ Failed to merge ${path.basename(filePath)}:`, err.message);
    }
  }

  // Add metadata
  mergedPdf.setTitle(`${frameworkName.toUpperCase()} Framework - Apple Documentation`);
  mergedPdf.setSubject(`Complete documentation for ${frameworkName}`);
  mergedPdf.setCreator('Apple Documentation Crawler');
  mergedPdf.setProducer('pdf-lib');
  mergedPdf.setCreationDate(new Date());
  mergedPdf.setModificationDate(new Date());

  // Note: pdf-lib doesn't support adding bookmarks/outlines in the same way as pdftk
  // For full bookmark support, you would need to use a different library or pdftk
  // This creates a basic merged PDF without interactive TOC bookmarks

  // Save the merged PDF
  const outputFileName = `${frameworkName}_FULL.pdf`;
  const outputPath = path.join(outputDir, outputFileName);

  const pdfBytes = await mergedPdf.save();
  fs.writeFileSync(outputPath, pdfBytes);

  console.log(`   ✅ Saved: ${outputFileName} (${tocEntries.length} sections, ${currentPage - 1} total pages)`);

  // Create a text TOC file
  const tocPath = path.join(outputDir, `${frameworkName}_TOC.txt`);
  const tocContent = [
    `Table of Contents - ${frameworkName.toUpperCase()}`,
    '='.repeat(60),
    '',
    ...tocEntries.map(entry => `Page ${entry.pageNumber.toString().padStart(4)}: ${entry.title}`),
    '',
    `Total: ${tocEntries.length} sections, ${currentPage - 1} pages`
  ].join('\n');

  fs.writeFileSync(tocPath, tocContent);
  console.log(`   📄 TOC saved: ${frameworkName}_TOC.txt`);

  return {
    framework: frameworkName,
    outputPath,
    sections: tocEntries.length,
    totalPages: currentPage - 1,
    tocPath
  };
}

async function mergeAllFrameworks() {
  console.log('📚 Apple Documentation PDF Merger\n');

  const docsDir = path.resolve(config.crawler.outputDir);
  const mergedDir = path.resolve(config.pdfMerge.outputDir);

  if (!fs.existsSync(docsDir)) {
    console.error(`❌ Documentation directory not found: ${docsDir}`);
    console.error('   Run "npm run crawl" or "npm run update" first.');
    process.exit(1);
  }

  // Create merged output directory
  fs.mkdirSync(mergedDir, { recursive: true });

  console.log(`Source: ${docsDir}`);
  console.log(`Output: ${mergedDir}\n`);
  console.log('─'.repeat(70));

  // Find all framework directories
  const frameworks = fs.readdirSync(docsDir)
    .filter(item => {
      const itemPath = path.join(docsDir, item);
      return fs.statSync(itemPath).isDirectory() && !item.startsWith('.');
    })
    .sort();

  if (frameworks.length === 0) {
    console.log('ℹ️  No framework directories found.');
    return;
  }

  console.log(`Found ${frameworks.length} frameworks to process\n`);

  const results = [];

  // Process each framework
  for (const framework of frameworks) {
    const frameworkPath = path.join(docsDir, framework);
    const result = await mergeFrameworkPDFs(framework, frameworkPath, mergedDir);

    if (result) {
      results.push(result);
    }
  }

  // Summary
  console.log('\n' + '='.repeat(70));
  console.log('📊 Merge Summary');
  console.log('='.repeat(70));

  if (results.length === 0) {
    console.log('No PDFs were merged.');
  } else {
    results.forEach(result => {
      console.log(`${result.framework}: ${result.sections} sections, ${result.totalPages} pages`);
    });

    const totalSections = results.reduce((sum, r) => sum + r.sections, 0);
    const totalPages = results.reduce((sum, r) => sum + r.totalPages, 0);

    console.log('─'.repeat(70));
    console.log(`Total: ${results.length} frameworks, ${totalSections} sections, ${totalPages} pages`);
  }

  console.log('='.repeat(70));
  console.log(`\n✅ Merged PDFs saved to: ${mergedDir}`);

  if (config.pdfMerge.addTableOfContents) {
    console.log('\n💡 Note: pdf-lib creates basic merged PDFs without interactive bookmarks.');
    console.log('   For full bookmark support, consider using pdftk:');
    console.log('   See the TOC.txt files for chapter listings.');
  }
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  mergeAllFrameworks().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
}

export { mergeAllFrameworks, mergeFrameworkPDFs };
