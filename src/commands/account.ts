import { Command } from 'commander';
import { logger } from '../utils/logger';
import { EVMClient } from '../clients/evm';
import { SuiClientManager } from '../clients/sui';
import { SUPPORTED_CHAINS, EVM_NETWORKS, SUI_NETWORKS, isEvmChain, isSuiChain } from '../config/networks';

export const accountCommand = new Command('account')
  .description('Show account information')
  .action(async () => {
    logger.info('📋 Account Information');
    
    try {
      console.log('\n👤 USER ACCOUNTS:');
      for (const chain of SUPPORTED_CHAINS) {
        try {
          if (isEvmChain(chain)) {
            const client = await EVMClient.getClient(chain, 'user');
            console.log(`  ${EVM_NETWORKS[chain].displayName}: ${client.address}`);
          } else if (isSuiChain(chain)) {
            const client = await SuiClientManager.getClient(chain, 'user');
            console.log(`  ${SUI_NETWORKS[chain].displayName}: ${client.address}`);
          }
        } catch (error) {
          console.log(`  ${chain}: Error - ${error.message}`);
        }
      }
      
      console.log('\n🔧 RESOLVER ACCOUNTS:');
      for (const chain of SUPPORTED_CHAINS) {
        try {
          if (isEvmChain(chain)) {
            const client = await EVMClient.getClient(chain, 'resolver');
            console.log(`  ${EVM_NETWORKS[chain].displayName}: ${client.address}`);
          } else if (isSuiChain(chain)) {
            const client = await SuiClientManager.getClient(chain, 'resolver');
            console.log(`  ${SUI_NETWORKS[chain].displayName}: ${client.address}`);
          }
        } catch (error) {
          console.log(`  ${chain}: Error - ${error.message}`);
        }
      }
    } catch (error) {
      logger.error(`Failed to show account info: ${error.message}`);
    }
  });
