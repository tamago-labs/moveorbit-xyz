import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { fromHEX } from '@mysten/sui/utils';
import { Transaction } from '@mysten/sui/transactions';
import { SuiNetworkConfig } from '../config/networks';
import { logger } from '../utils/logger';

export class SuiWalletClient {
  private client: SuiClient;
  private keypair: Ed25519Keypair;
  private address: string;

  constructor(privateKey: string, network: SuiNetworkConfig) {
    this.client = new SuiClient({ url: network.rpcUrl });
    
    try { 
      this.keypair = Ed25519Keypair.fromSecretKey(privateKey);
      this.address = this.keypair.getPublicKey().toSuiAddress();
      
      logger.debug('SUI wallet initialized', { address: this.address });
    } catch (error) {
      throw new Error(`Failed to initialize SUI wallet: ${error}`);
    }
  }

  getAddress(): string {
    return this.address;
  }

  getClient(): SuiClient {
    return this.client;
  }

  getKeypair(): Ed25519Keypair {
    return this.keypair;
  }

  async getBalance(): Promise<string> {
    try {
      const balance = await this.client.getBalance({
        owner: this.address,
      });
      return balance.totalBalance;
    } catch (error) {
      logger.error('Failed to get SUI balance', error);
      return '0';
    }
  }

  async getUSDCBalance(coinType: string): Promise<string> {
    try {
      const balance = await this.client.getBalance({
        owner: this.address,
        coinType,
      });
      return balance.totalBalance;
    } catch (error) {
      logger.debug('Failed to get USDC balance', error);
      return '0';
    }
  }

  async getAllCoins() {
    try {
      const coins = await this.client.getAllCoins({
        owner: this.address,
      });
      return coins.data;
    } catch (error) {
      logger.error('Failed to get all coins', error);
      return [];
    }
  }

  async getObjects() {
    try {
      const objects = await this.client.getOwnedObjects({
        owner: this.address,
      });
      return objects.data;
    } catch (error) {
      logger.error('Failed to get owned objects', error);
      return [];
    }
  }

  async signAndExecuteTransaction(tx: Transaction) {
    try {
      const result = await this.client.signAndExecuteTransaction({
        signer: this.keypair,
        transaction: tx,
        options: {
          showEvents: true,
          showEffects: true,
          showObjectChanges: true,
        },
      });
      return result;
    } catch (error) {
      logger.error('Failed to execute transaction', error);
      throw error;
    }
  }

  async requestTestTokens(): Promise<boolean> {
    try {
      logger.loading('Requesting SUI test tokens...');
      
      // SUI testnet faucet
      const response = await fetch('https://faucet.testnet.sui.io/gas', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          FixedAmountRequest: {
            recipient: this.address,
          },
        }),
      });

      if (response.ok) {
        logger.success('SUI test tokens requested successfully');
        return true;
      } else {
        logger.warn('Failed to request SUI test tokens');
        return false;
      }
    } catch (error) {
      logger.error('Error requesting SUI test tokens', error);
      return false;
    }
  }
}

let suiWalletInstance: SuiWalletClient | null = null;

export function createSuiWallet(network: SuiNetworkConfig): SuiWalletClient {
  const privateKey = process.env.SUI_PRIVATE_KEY;
  
  if (!privateKey) {
    throw new Error('SUI_PRIVATE_KEY not found in environment variables');
  }

  if (!suiWalletInstance) {
    suiWalletInstance = new SuiWalletClient(privateKey, network);
  }

  return suiWalletInstance;
}

export function getSuiWallet(): SuiWalletClient {
  if (!suiWalletInstance) {
    throw new Error('SUI wallet not initialized. Call createSuiWallet first.');
  }
  return suiWalletInstance;
}
