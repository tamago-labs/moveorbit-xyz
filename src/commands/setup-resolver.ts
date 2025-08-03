import { Command } from 'commander';
import { logger } from '../utils/logger';

export const setupResolverCommand = new Command('setup-resolver')
  .description('Setup cross-chain resolver')
  .action(async () => {
    logger.info('⚙️ Resolver setup functionality available in interactive mode');
    logger.info('Run: npm run dev');
  });
