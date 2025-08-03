import { Command } from 'commander';
import { logger } from '../utils/logger';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { SUPPORTED_CHAINS, EVM_NETWORKS, SUI_NETWORKS, isEvmChain } from '../config/networks';

export const statusCommand = new Command('status')
  .description('Check system status and contract addresses')
  .action(async () => {
    logger.info('📊 MoveOrbit System Status');
    console.log('==========================\n');
    
    console.log('🔗 DEPLOYED CONTRACTS:\n');
    
    for (const chain of SUPPORTED_CHAINS) {
      const contracts = CONTRACT_ADDRESSES[chain];
      const networkName = isEvmChain(chain) 
        ? EVM_NETWORKS[chain].displayName 
        : SUI_NETWORKS[chain].displayName;
      
      console.log(`${networkName}:`);
      console.log('================================================');
      
      if (isEvmChain(chain)) {
        console.log(`MockUSDC: ${contracts.mockUSDC}`);
        console.log(`LimitOrderProtocol: ${contracts.limitOrderProtocol}`);
      } else {
        console.log(`PackageID: ${contracts.packageId}`);
        console.log(`MockUSDC Global: ${contracts.usdcGlobal}`);
        console.log(`Resolver Registry: ${contracts.resolverRegistry}`);
        console.log(`Escrow Factory: ${contracts.escrowFactory}`);
      }
      console.log('');
    }

    console.log('💡 TIP: Use interactive mode for full functionality:');
    console.log('   npm run dev');
  });
