import { Command } from 'commander';
import { logger } from '../utils/logger';

export const registerMultivmCommand = new Command('register-multivm')
  .description('Register multi-VM resolver')
  .action(async () => {
    logger.info('🔗 Multi-VM registration available in interactive mode');
    logger.info('Run: npm run dev');
  });
