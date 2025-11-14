import cron from 'node-cron';
import { update } from './update.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load configuration
const configPath = path.join(__dirname, '..', 'config.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

/**
 * Scheduler for automated Apple documentation updates
 * Uses cron expressions to schedule regular crawls
 */

function validateCronExpression(expression) {
  return cron.validate(expression);
}

async function scheduledUpdate() {
  console.log('\n' + '='.repeat(70));
  console.log(`🕐 Scheduled update triggered at ${new Date().toISOString()}`);
  console.log('='.repeat(70) + '\n');

  try {
    await update();
    console.log('\n✅ Scheduled update completed successfully\n');
  } catch (err) {
    console.error('\n❌ Scheduled update failed:', err);
    console.error('Stack trace:', err.stack);
  }
}

function startScheduler() {
  if (!config.scheduling.enabled) {
    console.log('⚠️  Scheduling is disabled in config.json');
    console.log('   Set "scheduling.enabled" to true to enable automatic updates.');
    console.log('\n💡 You can manually run updates with: npm run update');
    process.exit(0);
  }

  const cronExpression = config.scheduling.cronExpression;

  if (!validateCronExpression(cronExpression)) {
    console.error('❌ Invalid cron expression:', cronExpression);
    console.error('   Please check your config.json');
    console.error('\n📖 Cron expression format:');
    console.error('   ┌───────────── minute (0 - 59)');
    console.error('   │ ┌───────────── hour (0 - 23)');
    console.error('   │ │ ┌───────────── day of month (1 - 31)');
    console.error('   │ │ │ ┌───────────── month (1 - 12)');
    console.error('   │ │ │ │ ┌───────────── day of week (0 - 6)');
    console.error('   │ │ │ │ │');
    console.error('   * * * * *');
    console.error('\n   Examples:');
    console.error('   "0 2 * * *"    - Every day at 2:00 AM');
    console.error('   "0 */6 * * *"  - Every 6 hours');
    console.error('   "0 0 * * 0"    - Every Sunday at midnight');
    process.exit(1);
  }

  console.log('🚀 Apple Documentation Scheduler Starting...\n');
  console.log('⚙️  Configuration:');
  console.log(`   Cron expression: ${cronExpression}`);
  console.log(`   Timezone: ${config.scheduling.timezone || 'System default'}`);
  console.log(`   Output directory: ${path.resolve(config.crawler.outputDir)}`);
  console.log();

  // Parse cron expression for human-readable description
  const [minute, hour, dayOfMonth, month, dayOfWeek] = cronExpression.split(' ');
  let scheduleDescription = 'Custom schedule';

  if (cronExpression === '0 2 * * *') {
    scheduleDescription = 'Daily at 2:00 AM';
  } else if (cronExpression === '0 */6 * * *') {
    scheduleDescription = 'Every 6 hours';
  } else if (cronExpression === '0 0 * * 0') {
    scheduleDescription = 'Weekly on Sunday at midnight';
  } else if (hour === '*' && minute !== '*') {
    scheduleDescription = 'Every hour';
  }

  console.log(`📅 Schedule: ${scheduleDescription}`);
  console.log(`⏱️  Next run will be at the scheduled time according to cron expression`);
  console.log();
  console.log('✅ Scheduler is now running. Press Ctrl+C to stop.');
  console.log('─'.repeat(70));

  // Schedule the task
  const task = cron.schedule(
    cronExpression,
    scheduledUpdate,
    {
      scheduled: true,
      timezone: config.scheduling.timezone || undefined
    }
  );

  // Optional: Run immediately on start (commented out by default)
  // Uncomment the next line if you want to run an update immediately when scheduler starts
  // scheduledUpdate();

  // Keep the process alive
  process.on('SIGINT', () => {
    console.log('\n\n🛑 Scheduler stopped by user');
    task.stop();
    process.exit(0);
  });

  process.on('SIGTERM', () => {
    console.log('\n\n🛑 Scheduler stopped');
    task.stop();
    process.exit(0);
  });
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  startScheduler();
}

export { startScheduler };
