import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { normalizeSuiAddress } from '@mysten/sui/utils';
import { SUI_NETWORKS, type SupportedChain, isSuiChain } from '../config/networks';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { logger } from '../utils/logger';

export interface SuiWalletClient {
  keypair: Ed25519Keypair;
  client: SuiClient;
  chain: SupportedChain;
  address: string;
}

export class SuiClientManager {
  private static instances: Map<string, SuiWalletClient> = new Map();

  static async getClient(chain: SupportedChain, userType: 'user' | 'resolver'): Promise<SuiWalletClient> {
    if (!isSuiChain(chain)) {
      throw new Error(`${chain} is not a SUI chain`);
    }

    const cacheKey = `${chain}-${userType}`;
    
    if (this.instances.has(cacheKey)) {
      return this.instances.get(cacheKey)!;
    }

    const privateKeyEnv = userType === 'user' ? 'USER_SUI_PRIVATE_KEY' : 'RESOLVER_SUI_PRIVATE_KEY';
    const privateKey = process.env[privateKeyEnv];
    
    if (!privateKey) {
      throw new Error(`Missing ${privateKeyEnv} in environment variables`);
    }

    // Create keypair from private key
    const keypair = Ed25519Keypair.fromSecretKey(privateKey);
    const address = normalizeSuiAddress(keypair.getPublicKey().toSuiAddress());

    const networkConfig = SUI_NETWORKS[chain];
    const client = new SuiClient({
      url: networkConfig.rpcUrl,
    });

    const walletClient = {
      keypair,
      client,
      chain,
      address,
    };

    this.instances.set(cacheKey, walletClient);
    return walletClient;
  }

  static async getBalance(chain: SupportedChain, userType: 'user' | 'resolver'): Promise<{
    sui: string;
    usdc: string;
  }> {
    const client = await this.getClient(chain, userType);
    
    try {
      // Get SUI balance
      const suiBalance = await client.client.getBalance({
        owner: client.address,
        coinType: '0x2::sui::SUI',
      });

      // Get USDC balance
      const usdcGlobal = CONTRACT_ADDRESSES[chain].usdcGlobal;
      let usdcBalance = '0';
      
      if (usdcGlobal) {
        try {
          const usdcCoins = await client.client.getCoins({
            owner: client.address,
            coinType: `${CONTRACT_ADDRESSES[chain].packageId}::mock_usdc::USDC`,
          });
          
          const totalUsdcBalance = usdcCoins.data.reduce((sum, coin) => {
            return sum + BigInt(coin.balance);
          }, BigInt(0));
          
          usdcBalance = (Number(totalUsdcBalance) / Math.pow(10, 6)).toString(); // USDC has 6 decimals
        } catch (usdcError) {
          logger.debug('No USDC balance found:', usdcError);
        }
      }

      return {
        sui: (Number(suiBalance.totalBalance) / Math.pow(10, 9)).toString(), // SUI has 9 decimals
        usdc: usdcBalance,
      };
    } catch (error) {
      logger.error('Error getting SUI balance:', error);
      return {
        sui: '0',
        usdc: '0',
      };
    }
  }

  static async mintUSDC(chain: SupportedChain, userType: 'user' | 'resolver', amount: string): Promise<string> {
    const client = await this.getClient(chain, userType);
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    const usdcGlobal = CONTRACT_ADDRESSES[chain].usdcGlobal;
    
    if (!packageId || !usdcGlobal) {
      throw new Error(`Missing contract addresses for ${chain}`);
    }

    const amountWithDecimals = Math.floor(parseFloat(amount) * Math.pow(10, 6)); // USDC has 6 decimals

    logger.info(`Minting ${amount} USDC to ${client.address} on ${chain}`);

    const tx = new Transaction();
    
    // Call the mint function
    tx.moveCall({
      target: `${packageId}::mock_usdc::mint`,
      arguments: [
        tx.object(usdcGlobal),
        tx.pure(amountWithDecimals),
        tx.pure(client.address),
      ],
    });

    try {
      const result = await client.client.signAndExecuteTransaction({
        signer: client.keypair,
        transaction: tx,
        options: {
          showEffects: true,
          showEvents: true,
        },
      });

      logger.info(`Transaction submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`USDC minted successfully`);
      } else {
        logger.error(`Transaction failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error minting USDC:', error);
      throw error;
    }
  }

  static async transferSui(
    chain: SupportedChain, 
    userType: 'user' | 'resolver', 
    recipient: string, 
    amount: string
  ): Promise<string> {
    const client = await this.getClient(chain, userType);
    
    const amountWithDecimals = Math.floor(parseFloat(amount) * Math.pow(10, 9)); // SUI has 9 decimals

    logger.info(`Transferring ${amount} SUI to ${recipient} on ${chain}`);

    const tx = new Transaction();
    
    const coin = tx.splitCoins(tx.gas, [tx.pure(amountWithDecimals)]);
    tx.transferObjects([coin], tx.pure(recipient));

    try {
      const result = await client.client.signAndExecuteTransaction({
        signer: client.keypair,
        transaction: tx,
        options: {
          showEffects: true,
        },
      });

      logger.info(`Transfer submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`SUI transferred successfully`);
      } else {
        logger.error(`Transfer failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error transferring SUI:', error);
      throw error;
    }
  }

  static async initializeResolver(chain: SupportedChain): Promise<string> {
    const client = await this.getClient(chain, 'resolver');
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    const escrowFactory = CONTRACT_ADDRESSES[chain].escrowFactory;
    
    if (!packageId || !escrowFactory) {
      throw new Error(`Missing contract addresses for ${chain}`);
    }

    logger.info(`Initializing resolver on ${chain}`);

    const tx = new Transaction();
    
    // Create a new resolver
    tx.moveCall({
      target: `${packageId}::interface::create_resolver`,
      arguments: [
        tx.pure(escrowFactory),
      ],
    });

    try {
      const result = await client.client.signAndExecuteTransaction({
        signer: client.keypair,
        transaction: tx,
        options: {
          showEffects: true,
          showEvents: true,
        },
      });

      logger.info(`Resolver initialization submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Resolver initialized successfully`);
      } else {
        logger.error(`Initialization failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error initializing resolver:', error);
      throw error;
    }
  }

  static async submitOrderAndSecret(
    chain: SupportedChain,
    resolverAddress: string,
    orderHash: string,
    secret: string
  ): Promise<string> {
    const client = await this.getClient(chain, 'resolver');
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    
    if (!packageId) {
      throw new Error(`Missing package ID for ${chain}`);
    }

    logger.info(`Submitting order and secret on ${chain}`);

    const tx = new Transaction();
    
    // Convert hex strings to byte arrays
    const orderHashBytes = Array.from((orderHash.startsWith('0x') ? orderHash.slice(2) : orderHash));
    const secretBytes = Array.from(Buffer.from(secret, 'utf8'));

    tx.moveCall({
      target: `${packageId}::interface::submit_order_and_secret`,
      arguments: [
        tx.object(resolverAddress),
        tx.pure(orderHashBytes),
        tx.pure(secretBytes),
      ],
    });

    try {
      const result = await client.client.signAndExecuteTransaction({
        signer: client.keypair,
        transaction: tx,
        options: {
          showEffects: true,
          showEvents: true,
        },
      });

      logger.info(`Order and secret submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Order and secret submitted successfully`);
      } else {
        logger.error(`Submission failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error submitting order and secret:', error);
      throw error;
    }
  }

  static async getGasCoins(chain: SupportedChain, userType: 'user' | 'resolver', amount: number = 1): Promise<void> {
    const client = await this.getClient(chain, userType);
    
    logger.info(`Getting ${amount} SUI from faucet for ${client.address}`);
    
    try {
      // Note: In a real implementation, you'd integrate with SUI faucet API
      // For now, we just log that this would request from faucet
      logger.info(`Please request SUI from faucet manually:`);
      logger.info(`Address: ${client.address}`);
      logger.info(`Faucet: https://discord.com/channels/916379725201563759/971488439931392130`);
    } catch (error) {
      logger.error('Error requesting from faucet:', error);
      throw error;
    }
  }
}
