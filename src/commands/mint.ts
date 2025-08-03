import { Command } from 'commander';
import prompts from 'prompts';
import { logger } from '../utils/logger';
import { EVMClient } from '../clients/evm';
import { SuiClientManager } from '../clients/sui';
import { SUPPORTED_CHAINS, EVM_NETWORKS, SUI_NETWORKS, isEvmChain, isSuiChain } from '../config/networks';

export const mintCommand = new Command('mint')
  .description('Mint USDC tokens')
  .option('-c, --chain <chain>', 'Chain to mint on')
  .option('-u, --user-type <type>', 'User type: user or resolver', 'user')
  .option('-a, --amount <amount>', 'Amount to mint', '1000')
  .action(async (options) => {
    let chain = options.chain;
    let userType = options.userType;
    let amount = options.amount;

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

    // Prompt for amount if not specified
    if (!amount || isNaN(parseFloat(amount))) {
      const result = await prompts({
        type: 'number',
        name: 'amount',
        message: 'Enter amount to mint (USDC):',
        initial: 1000,
        min: 1,
      });
      amount = result.amount?.toString();
    }

    if (!amount) {
      logger.error('No amount specified');
      return;
    }

    try {
      logger.loading(`Minting ${amount} USDC for ${userType} on ${chain}...`);
      
      let txHash: string;
      if (isEvmChain(chain)) {
        txHash = await EVMClient.mintUSDC(chain, userType, amount);
      } else if (isSuiChain(chain)) {
        txHash = await SuiClientManager.mintUSDC(chain, userType, amount);
      } else {
        throw new Error(`Unsupported chain: ${chain}`);
      }
      
      logger.complete(`Successfully minted ${amount} USDC!`);
      console.log(`Transaction: ${txHash}`);
      
    } catch (error) {
      logger.error(`Failed to mint USDC: ${error.message}`);
    }
  });
