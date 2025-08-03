import { Command } from 'commander';
import { logger } from '../utils/logger';

export const swapCommand = new Command('swap')
  .description('Execute cross-chain swaps')
  .action(async () => {
    logger.info('🌉 Cross-chain swap testing available in interactive mode');
    logger.info('Run: npm run dev');
  });
