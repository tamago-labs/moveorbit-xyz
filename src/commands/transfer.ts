import { Command } from 'commander';
import { logger } from '../utils/logger';

export const transferCommand = new Command('transfer')
  .description('Transfer tokens between accounts')
  .action(async () => {
    logger.info('🔄 Transfer functionality coming soon...');
    logger.info('Use the interactive mode (npm run dev) for full functionality');
  });
