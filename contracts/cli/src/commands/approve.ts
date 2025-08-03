import { Command } from 'commander';
import { logger } from '../utils/logger';

export const approveCommand = new Command('approve')
  .description('Approve token spending')
  .action(async () => {
    logger.info('✅ Approve functionality coming soon...');
    logger.info('Use the interactive mode (npm run dev) for full functionality');
  });
