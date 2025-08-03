import { SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { fromHEX, normalizeSuiAddress } from '@mysten/sui/utils';
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
            coinType: `0x6d956f92fd7c8a791643df6b6a7e0cb78b94d36524a99822a2ef2ac0f2227aaa::mock_usdc::MOCK_USDC`,
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
        tx.pure.u64(amountWithDecimals),
        tx.pure.address(client.address),
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
    
    const coin = tx.splitCoins(tx.gas, [tx.pure.u64(amountWithDecimals)]);
    tx.transferObjects([coin], tx.pure.address(recipient));

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

  static async createSharedResolver(chain: SupportedChain): Promise<string> {
    const client = await this.getClient(chain, 'resolver');
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    const escrowFactory = CONTRACT_ADDRESSES[chain].escrowFactory;
    
    if (!packageId || !escrowFactory) {
      throw new Error(`Missing contract addresses for ${chain}`);
    }

    logger.info(`Creating shared resolver on ${chain}`);

    const tx = new Transaction();
    
    // Create a shared resolver (aligned with test usage)
    tx.moveCall({
      target: `${packageId}::resolver::create_shared_resolver`,
      arguments: [
        tx.pure.address(escrowFactory),
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

      logger.info(`Shared resolver creation submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Shared resolver created successfully`);
      } else {
        logger.error(`Creation failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error creating shared resolver:', error);
      throw error;
    }
  }

  // Initialize protocol (calls escrow_factory::test_init)
  // static async initializeProtocol(chain: SupportedChain): Promise<string> {
  //   const client = await this.getClient(chain, 'resolver');
    
  //   const packageId = CONTRACT_ADDRESSES[chain].packageId;
    
  //   if (!packageId) {
  //     throw new Error(`Missing package ID for ${chain}`);
  //   }

  //   logger.info(`Initializing protocol on ${chain}`);

  //   const tx = new Transaction();
    
  //   // Initialize the protocol (creates factory and registry)
  //   tx.moveCall({
  //     target: `${packageId}::interface::initialize_protocol`,
  //     arguments: [],
  //   });

  //   try {
  //     const result = await client.client.signAndExecuteTransaction({
  //       signer: client.keypair,
  //       transaction: tx,
  //       options: {
  //         showEffects: true,
  //         showEvents: true,
  //       },
  //     });

  //     logger.info(`Protocol initialization submitted: ${result.digest}`);
      
  //     if (result.effects?.status?.status === 'success') {
  //       logger.info(`Protocol initialized successfully`);
  //     } else {
  //       logger.error(`Initialization failed:`, result.effects?.status);
  //     }

  //     return result.digest;
  //   } catch (error) {
  //     logger.error('Error initializing protocol:', error);
  //     throw error;
  //   }
  // }

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
    
    // Convert hex strings to byte arrays (aligned with test format)
    let orderHashBytes: number[];
    if (orderHash.startsWith('0x')) {
      orderHashBytes = Array.from(fromHEX(orderHash.slice(2)));
    } else {
      orderHashBytes = Array.from(fromHEX(orderHash));
    }
    
    const secretBytes = Array.from(Buffer.from(secret, 'utf8'));

    tx.moveCall({
      target: `${packageId}::resolver::submit_order_and_secret`,
      arguments: [
        tx.object(resolverAddress),
        tx.pure(orderHashBytes, 'vector<u8>'),
        tx.pure(secretBytes, 'vector<u8>'),
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

  static async authorizeResolver(
    chain: SupportedChain,
    factoryAddress: string,
    resolverAddress: string
  ): Promise<string> {
    const client = await this.getClient(chain, 'resolver');
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    
    if (!packageId) {
      throw new Error(`Missing package ID for ${chain}`);
    }

    logger.info(`Authorizing resolver on ${chain}`);

    const tx = new Transaction();
    
    tx.moveCall({
      target: `${packageId}::interface::authorize_resolver`,
      arguments: [
        tx.object(factoryAddress),
        tx.pure.address(resolverAddress),
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

      logger.info(`Resolver authorization submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Resolver authorized successfully`);
      } else {
        logger.error(`Authorization failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error authorizing resolver:', error);
      throw error;
    }
  }

  static async registerMultiVmResolver(
    chain: SupportedChain,
    resolverAddress: string,
    evmChainIds: bigint[],
    evmAddresses: string[]
  ): Promise<string> {
    const client = await this.getClient(chain, 'resolver');
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    
    if (!packageId) {
      throw new Error(`Missing package ID for ${chain}`);
    }

    logger.info(`Registering multi-VM resolver on ${chain}`);

    const tx = new Transaction();
    
    // Convert EVM addresses to byte arrays
    const evmAddressBytes = evmAddresses.map(addr => {
      if (addr.startsWith('0x')) {
        return Array.from(fromHEX(addr.slice(2)));
      }
      return Array.from(fromHEX(addr));
    });

    tx.moveCall({
      target: `${packageId}::interface::register_multi_vm_resolver`,
      arguments: [
        tx.object(resolverAddress),
        tx.pure(evmChainIds, 'vector<u256>'),
        tx.pure(evmAddressBytes, 'vector<vector<u8>>'),
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

      logger.info(`Multi-VM resolver registration submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Multi-VM resolver registered successfully`);
      } else {
        logger.error(`Registration failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error registering multi-VM resolver:', error);
      throw error;
    }
  }

  static async createDestinationEscrow<T>(
    chain: SupportedChain,
    params: {
      orderHash: string;
      secret: string;
      maker: string;
      taker: string;
      amount: number;
      safetyDeposit: number;
      timelocks: {
        dstWithdrawal: number;
        dstPublicWithdrawal: number;
        dstCancellation: number;
        dstPublicCancellation: number;
        srcWithdrawal: number;
        srcPublicWithdrawal: number;
        srcCancellation: number;
      };
      lockedCoin: any; // Coin object
      safetyCoin: any; // SUI coin object
    }
  ): Promise<string> {
    const client = await this.getClient(chain, 'user');
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    
    if (!packageId) {
      throw new Error(`Missing package ID for ${chain}`);
    }

    logger.info(`Creating destination escrow on ${chain}`);

    const tx = new Transaction();
    
    // Convert order hash to bytes
    let orderHashBytes: number[];
    if (params.orderHash.startsWith('0x')) {
      orderHashBytes = Array.from(fromHEX(params.orderHash.slice(2)));
    } else {
      orderHashBytes = Array.from(fromHEX(params.orderHash));
    }
    
    const secretBytes = Array.from(Buffer.from(params.secret, 'utf8'));

    tx.moveCall({
      target: `${packageId}::interface::create_destination_escrow`,
      typeArguments: [T],
      arguments: [
        tx.object(CONTRACT_ADDRESSES[chain].escrowFactory!),
        tx.pure(orderHashBytes, 'vector<u8>'),
        tx.pure(secretBytes, 'vector<u8>'),
        tx.pure.address(params.maker),
        tx.pure.address(params.taker),
        tx.pure.u64(params.amount),
        tx.pure.u64(params.safetyDeposit),
        // Timelock parameters
        tx.pure.u32(params.timelocks.dstWithdrawal),
        tx.pure.u32(params.timelocks.dstPublicWithdrawal),
        tx.pure.u32(params.timelocks.dstCancellation),
        tx.pure.u32(params.timelocks.dstPublicCancellation),
        tx.pure.u32(params.timelocks.srcWithdrawal),
        tx.pure.u32(params.timelocks.srcPublicWithdrawal),
        tx.pure.u32(params.timelocks.srcCancellation),
        // Assets
        params.lockedCoin,
        params.safetyCoin,
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

      logger.info(`Destination escrow creation submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Destination escrow created successfully`);
      } else {
        logger.error(`Creation failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error creating destination escrow:', error);
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

  // NEW: Complete cross-chain swap processing functions
  
  static async processCrossChainOrder(
    chain: SupportedChain,
    params: {
      orderHash: string;
      evmChainId: number;
      maker: string; // EVM address as hex string
      amount: number;
      secret: string;
      resolverAddress?: string;
    }
  ): Promise<string> {
    const client = await this.getClient(chain, 'resolver');
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    const factoryAddress = CONTRACT_ADDRESSES[chain].escrowFactory;
    
    if (!packageId || !factoryAddress) {
      throw new Error(`Missing contract addresses for ${chain}`);
    }

    logger.info(`Processing cross-chain order from EVM chain ${params.evmChainId}`);

    const tx = new Transaction();
    
    // Create EVM order structure for SUI processing
    const evmOrderData = {
      salt: BigInt(Date.now()),
      maker: params.maker,
      receiver: params.maker,
      makerAsset: '0x' + '0'.repeat(40), // Placeholder EVM address
      takerAsset: '0x' + '0'.repeat(40), // Placeholder EVM address  
      makingAmount: BigInt(params.amount * 1000000), // USDC 6 decimals
      takingAmount: BigInt(params.amount * 1000000),
      makerTraits: BigInt(0),
    };
    
    // Convert order hash to bytes
    let orderHashBytes: number[];
    if (params.orderHash.startsWith('0x')) {
      orderHashBytes = Array.from(fromHEX(params.orderHash.slice(2)));
    } else {
      orderHashBytes = Array.from(fromHEX(params.orderHash));
    }
    
    const secretBytes = Array.from(Buffer.from(params.secret, 'utf8'));
    
    // Get USDC coins for the escrow
    const usdcCoins = await client.client.getCoins({
      owner: client.address,
      coinType: `${packageId}::mock_usdc::MOCK_USDC`,
    });
    
    if (usdcCoins.data.length === 0) {
      throw new Error('Resolver has no USDC coins to create escrow');
    }
    
    // Use the first USDC coin
    const usdcCoin = usdcCoins.data[0];
    const amountNeeded = params.amount * 1000000; // 6 decimals
    
    if (Number(usdcCoin.balance) < amountNeeded) {
      throw new Error(`Insufficient USDC balance. Need ${amountNeeded}, have ${usdcCoin.balance}`);
    }
    
    // Get SUI for safety deposit  
    const safetyDepositAmount = 1000000000; // 1 SUI in mist
    
    // Create the cross-chain escrow
    tx.moveCall({
      target: `${packageId}::interface::process_evm_to_sui_swap`,
      typeArguments: [`${packageId}::mock_usdc::MOCK_USDC`],
      arguments: [
        tx.object(params.resolverAddress || client.address), // Resolver object
        tx.object(factoryAddress), // Factory
        // EVM order parameters (simplified for SUI processing)
        tx.pure(evmOrderData.salt, 'u256'),
        tx.pure(Array.from(fromHEX(evmOrderData.maker.slice(2))), 'vector<u8>'),
        tx.pure(Array.from(fromHEX(evmOrderData.receiver.slice(2))), 'vector<u8>'),
        tx.pure(Array.from(fromHEX(evmOrderData.makerAsset.slice(2))), 'vector<u8>'),
        tx.pure(Array.from(fromHEX(evmOrderData.takerAsset.slice(2))), 'vector<u8>'),
        tx.pure(evmOrderData.makingAmount, 'u256'),
        tx.pure(evmOrderData.takingAmount, 'u256'),
        tx.pure(evmOrderData.makerTraits, 'u256'),
        // Cross-chain parameters
        tx.pure(orderHashBytes, 'vector<u8>'),
        tx.pure(Array.from(Buffer.from('mock_sig_r')), 'vector<u8>'), // Mock signature
        tx.pure(Array.from(Buffer.from('mock_sig_vs')), 'vector<u8>'), // Mock signature
        tx.pure(params.evmChainId, 'u256'), // EVM chain ID
        tx.pure(1, 'u256'), // SUI chain ID
        // Assets
        tx.object(usdcCoin.coinObjectId),
        tx.splitCoins(tx.gas, [tx.pure.u64(safetyDepositAmount)]), // Safety deposit in SUI
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

      logger.info(`Cross-chain order processing submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Cross-chain order processed successfully`);
        
        // Log any events
        if (result.events && result.events.length > 0) {
          logger.info('Events emitted:');
          result.events.forEach((event, index) => {
            console.log(`  Event ${index + 1}: ${event.type}`);
          });
        }
      } else {
        logger.error(`Processing failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error processing cross-chain order:', error);
      throw error;
    }
  }
  
  static async completeSwapWithSecret(
    chain: SupportedChain,
    params: {
      escrowId: string;
      orderHash: string;
      secret: string;
      resolverAddress?: string;
    }
  ): Promise<string> {
    const client = await this.getClient(chain, 'user'); // User completes the swap
    
    const packageId = CONTRACT_ADDRESSES[chain].packageId;
    
    if (!packageId) {
      throw new Error(`Missing package ID for ${chain}`);
    }

    logger.info(`Completing swap with secret reveal on ${chain}`);

    const tx = new Transaction();
    
    // Convert order hash to bytes
    let orderHashBytes: number[];
    if (params.orderHash.startsWith('0x')) {
      orderHashBytes = Array.from(fromHEX(params.orderHash.slice(2)));
    } else {
      orderHashBytes = Array.from(fromHEX(params.orderHash));
    }
    
    const secretBytes = Array.from(Buffer.from(params.secret, 'utf8'));

    tx.moveCall({
      target: `${packageId}::interface::complete_swap_with_secret`,
      typeArguments: [`${packageId}::mock_usdc::MOCK_USDC`],
      arguments: [
        tx.object(params.resolverAddress || '0x0'), // Resolver object (if needed)
        tx.object(params.escrowId), // Escrow object
        tx.pure(orderHashBytes, 'vector<u8>'),
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

      logger.info(`Swap completion submitted: ${result.digest}`);
      
      if (result.effects?.status?.status === 'success') {
        logger.info(`Swap completed successfully with secret reveal`);
        
        // Log any events
        if (result.events && result.events.length > 0) {
          logger.info('Events emitted:');
          result.events.forEach((event, index) => {
            console.log(`  Event ${index + 1}: ${event.type}`);
          });
        }
      } else {
        logger.error(`Completion failed:`, result.effects?.status);
      }

      return result.digest;
    } catch (error) {
      logger.error('Error completing swap with secret:', error);
      throw error;
    }
  }
  
  static async simulateEVMEventProcessing(
    chain: SupportedChain,
    params: {
      orderHash: string;
      evmChainId: number;
      evmTxHash: string;
      maker: string;
      amount: number;
      secret: string;
    }
  ): Promise<{ escrowId: string; processingTx: string }> {
    const client = await this.getClient(chain, 'resolver');
    
    logger.info(`Simulating EVM event processing for order ${params.orderHash}`);
    
    // Step 1: Process the cross-chain order (as if we received EVM event)
    logger.loading('Step 1: Processing cross-chain order from EVM event...');
    
    try {
      const processingTx = await this.processCrossChainOrder(chain, {
        orderHash: params.orderHash,
        evmChainId: params.evmChainId,
        maker: params.maker,
        amount: params.amount,
        secret: params.secret,
      });
      
      logger.success(`✅ Cross-chain order processed: ${processingTx}`);
      
      // In a real implementation, we'd extract the escrow ID from events
      // For simulation, we'll create a mock escrow ID
      const mockEscrowId = '0x' + Buffer.from(
        `escrow_${params.orderHash.slice(-8)}_${Date.now()}`
      ).toString('hex').slice(0, 64).padEnd(64, '0');
      
      return {
        escrowId: mockEscrowId,
        processingTx,
      };
      
    } catch (error) {
      logger.error('Failed to process cross-chain order:', error);
      throw error;
    }
  }
  
  // static async getSharedObjects(chain: SupportedChain): Promise<{
  //   resolver?: string;
  //   factory?: string;
  //   registry?: string;
  // }> {
  //   const client = await this.getClient(chain, 'resolver');
  //   const packageId = CONTRACT_ADDRESSES[chain].packageId;
    
  //   if (!packageId) {
  //     throw new Error(`Missing package ID for ${chain}`);
  //   }
    
  //   try {
  //     // Query for shared objects created by our package
  //     const objects = await client.client.getOwnedObjects({
  //       owner: client.address,
  //       filter: {
  //         StructType: `${packageId}::resolver::Resolver`,
  //       },
  //       options: {
  //         showContent: true,
  //       },
  //     });
      
  //     const result: { resolver?: string; factory?: string; registry?: string } = {};
      
  //     // Look for resolver objects
  //     objects.data.forEach(obj => {
  //       if (obj.data?.content && 'fields' in obj.data.content) {
  //         const objectId = obj.data.objectId;
  //         if (obj.data.content.type.includes('::resolver::Resolver')) {
  //           result.resolver = objectId;
  //         }
  //       }
  //     });
      
  //     // Add factory and registry from config
  //     result.factory = CONTRACT_ADDRESSES[chain].escrowFactory;
  //     result.registry = CONTRACT_ADDRESSES[chain].resolverRegistry;
      
  //     return result;
  //   } catch (error) {
  //     logger.debug('Error querying shared objects:', error);
  //     return {
  //       factory: CONTRACT_ADDRESSES[chain].escrowFactory,
  //       registry: CONTRACT_ADDRESSES[chain].resolverRegistry,
  //     };
  //   }
  // }

}
