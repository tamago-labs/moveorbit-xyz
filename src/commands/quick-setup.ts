import { Command } from 'commander';
import { logger } from '../utils/logger';

export const quickSetupCommand = new Command('quick-setup')
  .description('Quick setup for testing')
  .action(async () => {
    logger.info('⚡ Quick setup available in interactive mode');
    logger.info('Run: npm run dev');
  });
