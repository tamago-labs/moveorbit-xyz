import { createWalletClient, createPublicClient, http, parseEther, formatEther, getContract } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia, arbitrumSepolia } from 'viem/chains';
import { EVM_NETWORKS, type SupportedChain, isEvmChain } from '../config/networks';
import { CONTRACT_ADDRESSES, MOCK_USDC_ABI, LIMIT_ORDER_PROTOCOL_ABI } from '../config/contracts';
import { logger } from '../utils/logger';

// Function to get Avalanche Fuji chain config at runtime
function getAvalancheFujiChain() {
  return {
    id: 43113,
    name: 'Avalanche Fuji',
    network: 'avalanche-fuji',
    nativeCurrency: {
      decimals: 18,
      name: 'AVAX',
      symbol: 'AVAX',
    },
    rpcUrls: {
      default: {
        http: [process.env.AVALANCHE_FUJI_RPC || 'https://api.avax-test.network/ext/bc/C/rpc'],
      },
    },
    blockExplorers: {
      default: { name: 'SnowTrace', url: 'https://testnet.snowtrace.io' },
    },
    testnet: true,
  } as const;
}

export interface EVMWalletClient {
  account: any;
  walletClient: any;
  publicClient: any;
  chain: SupportedChain;
  address: string;
}

export class EVMClient {
  private static instances: Map<string, EVMWalletClient> = new Map();

  static async getClient(chain: SupportedChain, userType: 'user' | 'resolver'): Promise<EVMWalletClient> {
    if (!isEvmChain(chain)) {
      throw new Error(`${chain} is not an EVM chain`);
    }

    const cacheKey = `${chain}-${userType}`;
    
    if (this.instances.has(cacheKey)) {
      return this.instances.get(cacheKey)!;
    }

    const privateKeyEnv = userType === 'user' ? 'USER_EVM_PRIVATE_KEY' : 'RESOLVER_EVM_PRIVATE_KEY';
    const privateKey = process.env[privateKeyEnv];
    
    if (!privateKey) {
      throw new Error(`Missing ${privateKeyEnv} in environment variables`);
    }

    const account = privateKeyToAccount(privateKey as `0x${string}`);
    const networkConfig = EVM_NETWORKS[chain];
    
    // Get the appropriate chain object at runtime
    let chainObject;
    switch (chain) {
      case 'eth-sepolia':
        chainObject = sepolia;
        break;
      case 'avax-fuji':
        chainObject = getAvalancheFujiChain();
        break;
      case 'arb-sepolia':
        chainObject = arbitrumSepolia;
        break;
      default:
        throw new Error(`Unsupported chain: ${chain}`);
    }

    const publicClient = createPublicClient({
      chain: chainObject,
      transport: http(networkConfig.rpcUrl),
    });

    const walletClient = createWalletClient({
      account,
      chain: chainObject,
      transport: http(networkConfig.rpcUrl),
    });

    const client = {
      account,
      walletClient,
      publicClient,
      chain,
      address: account.address,
    };

    this.instances.set(cacheKey, client);
    return client;
  }

  static async getBalance(chain: SupportedChain, userType: 'user' | 'resolver'): Promise<{
    native: string;
    usdc: string;
  }> {
    const client = await this.getClient(chain, userType);
    
    // Get native token balance
    const nativeBalance = await client.publicClient.getBalance({
      address: client.address,
    });

    // Get USDC balance
    const usdcContract = getContract({
      address: CONTRACT_ADDRESSES[chain].mockUSDC as `0x${string}`,
      abi: MOCK_USDC_ABI,
      client: client.publicClient,
    });

    const usdcBalance = await usdcContract.read.balanceOf([client.address]);
    const decimals = await usdcContract.read.decimals();

    return {
      native: formatEther(nativeBalance),
      usdc: (Number(usdcBalance) / Math.pow(10, Number(decimals))).toString(),
    };
  }

  static async mintUSDC(chain: SupportedChain, userType: 'user' | 'resolver', amount: string): Promise<string> {
    const client = await this.getClient(chain, userType);
    
    const usdcContract = getContract({
      address: CONTRACT_ADDRESSES[chain].mockUSDC as `0x${string}`,
      abi: MOCK_USDC_ABI,
      client: client.walletClient,
    });

    const decimals = await usdcContract.read.decimals();
    const amountWithDecimals = BigInt(parseFloat(amount) * Math.pow(10, Number(decimals)));

    logger.info(`Minting ${amount} USDC to ${client.address} on ${chain}`);

    const hash = await usdcContract.write.mint([
      client.address,
      amountWithDecimals,
    ]);

    logger.info(`Transaction submitted: ${hash}`);
    
    // Wait for confirmation
    const receipt = await client.publicClient.waitForTransactionReceipt({
      hash,
      confirmations: 2,
    });

    logger.info(`Transaction confirmed in block ${receipt.blockNumber}`);
    return hash;
  }

  static async approveUSDC(
    chain: SupportedChain, 
    userType: 'user' | 'resolver', 
    spender: string, 
    amount: string
  ): Promise<string> {
    const client = await this.getClient(chain, userType);
    
    const usdcContract = getContract({
      address: CONTRACT_ADDRESSES[chain].mockUSDC as `0x${string}`,
      abi: MOCK_USDC_ABI,
      client: client.walletClient,
    });

    const decimals = await usdcContract.read.decimals();
    const amountWithDecimals = amount === 'max' 
      ? BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
      : BigInt(parseFloat(amount) * Math.pow(10, Number(decimals)));

    logger.info(`Approving ${amount} USDC for ${spender} on ${chain}`);

    const hash = await usdcContract.write.approve([
      spender as `0x${string}`,
      amountWithDecimals,
    ]);

    logger.info(`Approval transaction submitted: ${hash}`);
    
    const receipt = await client.publicClient.waitForTransactionReceipt({
      hash,
      confirmations: 1,
    });

    logger.info(`Approval confirmed in block ${receipt.blockNumber}`);
    return hash;
  }

  static async createOrder(chain: SupportedChain, params: {
    maker: string;
    receiver: string;
    makerAsset: string;
    takerAsset: string;
    makingAmount: string;
    takingAmount: string;
    salt?: string;
  }): Promise<any> {
    const client = await this.getClient(chain, 'user');
    
    const lopContract = getContract({
      address: CONTRACT_ADDRESSES[chain].limitOrderProtocol as `0x${string}`,
      abi: LIMIT_ORDER_PROTOCOL_ABI,
      client: client.publicClient,
    });

    const decimals = 6; // USDC has 6 decimals
    const makingAmountWithDecimals = BigInt(parseFloat(params.makingAmount) * Math.pow(10, decimals));
    const takingAmountWithDecimals = BigInt(parseFloat(params.takingAmount) * Math.pow(10, decimals));

    const order = {
      salt: params.salt ? BigInt(params.salt) : BigInt(Date.now()),
      maker: params.maker as `0x${string}`,
      receiver: params.receiver as `0x${string}`,
      makerAsset: params.makerAsset as `0x${string}`,
      takerAsset: params.takerAsset as `0x${string}`,
      makingAmount: makingAmountWithDecimals,
      takingAmount: takingAmountWithDecimals,
      makerTraits: BigInt(0),
    };

    // Get order hash
    const orderHash = await lopContract.read.hashOrder([order]);

    return {
      order,
      orderHash,
      chain,
    };
  }

  static async signOrder(chain: SupportedChain, order: any): Promise<{
    r: string;
    vs: string;
  }> {
    const client = await this.getClient(chain, 'user');
    
    const lopContract = getContract({
      address: CONTRACT_ADDRESSES[chain].limitOrderProtocol as `0x${string}`,
      abi: LIMIT_ORDER_PROTOCOL_ABI,
      client: client.publicClient,
    });

    const orderHash = await lopContract.read.hashOrder([order]);
    
    // Sign the order hash
    const signature = await client.account.signMessage({
      message: { raw: orderHash as `0x${string}` },
    });

    // Parse signature into r and vs format (as used in the test)
    const r = signature.slice(0, 66); // 0x + 32 bytes
    const s = signature.slice(66, 130); // 32 bytes
    const v = signature.slice(130, 132); // 1 byte

    // Convert to vs format (v-27 in high bit + s)
    const vNum = parseInt(v, 16);
    const vs = '0x' + (vNum - 27 === 1 ? '8' : '0') + s.slice(1);

    return { r, vs };
  }
}
