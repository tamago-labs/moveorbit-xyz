import { Command } from 'commander';
import prompts from 'prompts';
import { logger } from '../utils/logger';
import { EVMClient } from '../clients/evm';
import { SuiClientManager } from '../clients/sui';
import { SUPPORTED_CHAINS, EVM_NETWORKS, SUI_NETWORKS, isEvmChain, isSuiChain } from '../config/networks';

export const balanceCommand = new Command('balance')
  .description('Check account balances')
  .option('-c, --chain <chain>', 'Chain to check balance on')
  .option('-u, --user-type <type>', 'User type: user or resolver', 'user')
  .action(async (options) => {
    let chain = options.chain;
    let userType = options.userType;

    // If no chain specified, prompt for it
    if (!chain) {
      const result = await prompts({
        type: 'select',
        name: 'chain',
        message: 'Select chain:',
        choices: SUPPORTED_CHAINS.map(chain => ({
          title: isEvmChain(chain) ? EVM_NETWORKS[chain].displayName : SUI_NETWORKS[chain].displayName,
          value: chain,
        })),
      });
      chain = result.chain;
    }

    if (!chain) {
      logger.error('No chain selected');
      return;
    }

    // If no user type specified, prompt for it
    if (!['user', 'resolver'].includes(userType)) {
      const result = await prompts({
        type: 'select',
        name: 'userType',
        message: 'Select account type:',
        choices: [
          { title: 'User', value: 'user' },
          { title: 'Resolver', value: 'resolver' },
        ],
      });
      userType = result.userType;
    }

    if (!userType) {
      logger.error('No user type selected');
      return;
    }

    try {
      if (isEvmChain(chain)) {
        const balance = await EVMClient.getBalance(chain, userType);
        const networkInfo = EVM_NETWORKS[chain];
        const client = await EVMClient.getClient(chain, userType);
        
        logger.success(`${userType.toUpperCase()} Balance on ${networkInfo.displayName}:`);
        console.log(`  Address: ${client.address}`);
        console.log(`  ${networkInfo.nativeCurrency.symbol}: ${balance.native}`);
        console.log(`  USDC: ${balance.usdc}`);
        
      } else if (isSuiChain(chain)) {
        const balance = await SuiClientManager.getBalance(chain, userType);
        const networkInfo = SUI_NETWORKS[chain];
        const client = await SuiClientManager.getClient(chain, userType);
        
        logger.success(`${userType.toUpperCase()} Balance on ${networkInfo.displayName}:`);
        console.log(`  Address: ${client.address}`);
        console.log(`  SUI: ${balance.sui}`);
        console.log(`  USDC: ${balance.usdc}`);
      }
    } catch (error) {
      logger.error(`Failed to get balance: ${error.message}`);
    }
  });
