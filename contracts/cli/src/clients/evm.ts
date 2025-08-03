import { createWalletClient, createPublicClient, http, PublicClient, WalletClient, Account, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { NetworkConfig } from '../config/networks';
import { logger } from '../utils/logger';

export class EvmWalletClient {
  private publicClient: PublicClient;
  private walletClient: WalletClient;
  private account: Account;
  private network: NetworkConfig;

  constructor(privateKey: string, network: NetworkConfig) {
    this.network = network;
    
    try {
      // Create account from private key
      this.account = privateKeyToAccount(privateKey as `0x${string}`);
      
      // Define custom chain for viem
      const chain = defineChain({
        id: network.chainId,
        name: network.name,
        nativeCurrency: network.nativeCurrency,
        rpcUrls: {
          default: { http: [network.rpcUrl] },
        },
        blockExplorers: {
          default: { name: 'Explorer', url: network.blockExplorer },
        },
      });

      // Create clients
      this.publicClient = createPublicClient({
        chain,
        transport: http(network.rpcUrl),
      });

      this.walletClient = createWalletClient({
        account: this.account,
        chain,
        transport: http(network.rpcUrl),
      });

      logger.debug(`EVM wallet initialized for ${network.displayName}`, { 
        address: this.account.address,
        chainId: network.chainId 
      });
    } catch (error) {
      throw new Error(`Failed to initialize EVM wallet for ${network.displayName}: ${error}`);
    }
  }

  getAddress(): string {
    return this.account.address;
  }

  getAccount(): Account {
    return this.account;
  }

  getPublicClient(): PublicClient {
    return this.publicClient;
  }

  getWalletClient(): WalletClient {
    return this.walletClient;
  }

  getNetwork(): NetworkConfig {
    return this.network;
  }

  async getBalance(): Promise<bigint> {
    try {
      const balance = await this.publicClient.getBalance({
        address: this.account.address,
      });
      return balance;
    } catch (error) {
      logger.error(`Failed to get balance on ${this.network.displayName}`, error);
      return 0n;
    }
  }

  async getTokenBalance(tokenAddress: string, abi: any): Promise<bigint> {
    try {
      const balance = await this.publicClient.readContract({
        address: tokenAddress as `0x${string}`,
        abi,
        functionName: 'balanceOf',
        args: [this.account.address],
      });
      return balance as bigint;
    } catch (error) {
      logger.error(`Failed to get token balance on ${this.network.displayName}`, error);
      return 0n;
    }
  }

  async getTokenDecimals(tokenAddress: string, abi: any): Promise<number> {
    try {
      const decimals = await this.publicClient.readContract({
        address: tokenAddress as `0x${string}`,
        abi,
        functionName: 'decimals',
      });
      return decimals as number;
    } catch (error) {
      logger.error(`Failed to get token decimals on ${this.network.displayName}`, error);
      return 18;
    }
  }

  async sendTransaction(params: {
    to: string;
    value?: bigint;
    data?: string;
  }) {
    try {
      const hash = await this.walletClient.sendTransaction({
        to: params.to as `0x${string}`,
        value: params.value || 0n,
        data: params.data as `0x${string}`,
      });
      
      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return receipt;
    } catch (error) {
      logger.error(`Failed to send transaction on ${this.network.displayName}`, error);
      throw error;
    }
  }

  async writeContract(params: {
    address: string;
    abi: any;
    functionName: string;
    args?: any[];
    value?: bigint;
  }) {
    try {
      const hash = await this.walletClient.writeContract({
        address: params.address as `0x${string}`,
        abi: params.abi,
        functionName: params.functionName,
        args: params.args || [],
        value: params.value,
      });
      
      const receipt = await this.publicClient.waitForTransactionReceipt({ hash });
      return receipt;
    } catch (error) {
      logger.error(`Failed to write contract on ${this.network.displayName}`, error);
      throw error;
    }
  }

  async estimateGas(params: {
    to: string;
    data?: string;
    value?: bigint;
  }): Promise<bigint> {
    try {
      const gas = await this.publicClient.estimateGas({
        account: this.account,
        to: params.to as `0x${string}`,
        data: params.data as `0x${string}`,
        value: params.value,
      });
      return gas;
    } catch (error) {
      logger.error(`Failed to estimate gas on ${this.network.displayName}`, error);
      return 100000n;
    }
  }
}

const evmWalletInstances: Map<string, EvmWalletClient> = new Map();

export function createEvmWallet(network: NetworkConfig): EvmWalletClient {
  const privateKey = process.env.EVM_PRIVATE_KEY;
  
  if (!privateKey) {
    throw new Error('EVM_PRIVATE_KEY not found in environment variables');
  }

  const cacheKey = network.name;
  
  if (!evmWalletInstances.has(cacheKey)) {
    const wallet = new EvmWalletClient(privateKey, network);
    evmWalletInstances.set(cacheKey, wallet);
  }

  return evmWalletInstances.get(cacheKey)!;
}

export function getEvmWallet(networkName: string): EvmWalletClient {
  const wallet = evmWalletInstances.get(networkName);
  if (!wallet) {
    throw new Error(`EVM wallet for ${networkName} not initialized. Call createEvmWallet first.`);
  }
  return wallet;
}

export function getAllEvmWallets(): Map<string, EvmWalletClient> {
  return evmWalletInstances;
}
