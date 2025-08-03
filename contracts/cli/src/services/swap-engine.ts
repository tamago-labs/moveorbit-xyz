import { formatUnits, parseUnits, keccak256, encodePacked } from 'viem';
import { Transaction } from '@mysten/sui/transactions';
import { createEvmWallet } from '../clients/evm';
import { createSuiWallet } from '../clients/sui';
import { EVM_NETWORKS, SUI_NETWORKS, isEvmChain } from '../config/networks';
import { getContractAddress, MOCK_USDC_ABI, LIMIT_ORDER_PROTOCOL_ABI } from '../config/contracts';
import { DECIMALS } from '../config/constants';
import { secretManager } from './secrets';
import { resolverService } from './resolver';
import { logger } from '../utils/logger';

export interface SwapParams {
  fromChain: string;
  toChain: string;
  amount: number;
  resolverAddress?: string;
}

export interface Order {
  salt: bigint;
  maker: string;
  receiver: string;
  makerAsset: string;
  takerAsset: string;
  makingAmount: bigint;
  takingAmount: bigint;
  makerTraits: bigint;
}

export class SwapEngine {
  async executeSwap(params: SwapParams): Promise<string> {
    const { fromChain, toChain, amount } = params;

    logger.info(`🔄 Executing swap: ${amount} USDC from ${fromChain} to ${toChain}`);

    if (isEvmChain(fromChain) && toChain === 'sui-testnet') {
      return this.executeEvmToSuiSwap(params);
    } else if (fromChain === 'sui-testnet' && isEvmChain(toChain)) {
      return this.executeSuiToEvmSwap(params);
    } else if (isEvmChain(fromChain) && isEvmChain(toChain)) {
      return this.executeEvmToEvmSwap(params);
    } else {
      throw new Error(`Unsupported swap route: ${fromChain} -> ${toChain}`);
    }
  }

  private async executeEvmToSuiSwap(params: SwapParams): Promise<string> {
    const { fromChain, toChain, amount, resolverAddress } = params;
    
    logger.loading('1. Creating EVM order...');
    
    // Step 1: Create order on EVM side
    const order = await this.createEvmOrder(fromChain, toChain, amount);
    const orderHash = await this.getOrderHash(fromChain, order);
    
    logger.info(`Order hash: ${orderHash}`);
    
    // Step 2: Check and ensure approval
    logger.loading('2. Checking USDC approval...');
    await this.ensureUSDCApproval(fromChain, amount);
    
    // Step 3: Generate secret
    logger.loading('3. Generating secret...');
    const swapSecret = secretManager.createSecretForOrder(orderHash);
    
    // Step 4: Submit secret to SUI resolver
    if (resolverAddress) {
      logger.loading('4. Submitting secret to SUI resolver...');
      await resolverService.submitOrderAndSecret(
        resolverAddress,
        orderHash,
        swapSecret.secret
      );
    }
    
    // Step 5: Execute cross-chain swap on SUI
    logger.loading('5. Processing swap on SUI...');
    const suiTxHash = await this.processSuiSwap(order, orderHash, swapSecret.secret, amount);
    
    logger.success('✅ Cross-chain swap completed!');
    return suiTxHash;
  }

  private async executeSuiToEvmSwap(params: SwapParams): Promise<string> {
    // Implementation for SUI to EVM swaps
    throw new Error('SUI to EVM swaps not yet implemented');
  }

  private async executeEvmToEvmSwap(params: SwapParams): Promise<string> {
    const { fromChain, toChain, amount } = params;
    
    logger.loading('1. Creating EVM order...');
    
    // Create order
    const order = await this.createEvmOrder(fromChain, toChain, amount);
    const orderHash = await this.getOrderHash(fromChain, order);
    
    // Check and ensure approval
    logger.loading('2. Checking USDC approval...');
    await this.ensureUSDCApproval(fromChain, amount);
    
    // Sign order
    logger.loading('3. Signing order...');
    const signature = await this.signOrder(fromChain, order);
    
    // Execute direct EVM swap
    logger.loading('4. Executing EVM swap...');
    const txHash = await this.executeEvmSwap(toChain, order, signature);
    
    logger.success('✅ EVM swap completed!');
    return txHash;
  }

  private async ensureUSDCApproval(chain: string, amount: number): Promise<void> {
    const network = EVM_NETWORKS[chain];
    const wallet = createEvmWallet(network);
    const usdcAddress = getContractAddress(chain, 'mockUSDC');
    const lopAddress = getContractAddress(chain, 'limitOrderProtocol');
    
    const amountWei = parseUnits(amount.toString(), DECIMALS.USDC);
    
    try {
      // Check current allowance
      const currentAllowance = await wallet.getPublicClient().readContract({
        address: usdcAddress as `0x${string}`,
        abi: MOCK_USDC_ABI,
        functionName: 'allowance',
        args: [wallet.getAddress(), lopAddress],
      }) as bigint;
      
      logger.debug(`Current allowance: ${formatUnits(currentAllowance, DECIMALS.USDC)} USDC`);
      
      // If allowance is sufficient, no need to approve
      if (currentAllowance >= amountWei) {
        logger.info(`✅ USDC approval sufficient: ${formatUnits(currentAllowance, DECIMALS.USDC)} USDC`);
        return;
      }
      
      // Need to approve
      logger.info(`🔒 Approving ${amount} USDC for LimitOrderProtocol...`);
      
      const receipt = await wallet.writeContract({
        address: usdcAddress,
        abi: MOCK_USDC_ABI,
        functionName: 'approve',
        args: [lopAddress, amountWei],
      });
      
      logger.success(`✅ USDC approved successfully!`);
      logger.debug(`Approval transaction: ${network.blockExplorer}/tx/${receipt.transactionHash}`);
      
    } catch (error) {
      logger.error('Failed to check/approve USDC:', error);
      throw new Error(`USDC approval failed: ${error}`);
    }
  }

  private async createEvmOrder(fromChain: string, toChain: string, amount: number): Promise<Order> {
    const fromNetwork = EVM_NETWORKS[fromChain];
    const fromWallet = createEvmWallet(fromNetwork);
    
    const makerAsset = getContractAddress(fromChain, 'mockUSDC');
    
    let takerAsset: string;
    if (isEvmChain(toChain)) {
      takerAsset = getContractAddress(toChain, 'mockUSDC');
    } else {
      // For SUI, use a placeholder address
      takerAsset = '0x0000000000000000000000000000000000000002';
    }

    const amountWei = parseUnits(amount.toString(), DECIMALS.USDC);
    const salt = BigInt(Date.now());

    const order: Order = {
      salt,
      maker: fromWallet.getAddress(),
      receiver: fromWallet.getAddress(),
      makerAsset,
      takerAsset,
      makingAmount: amountWei,
      takingAmount: amountWei, // 1:1 swap for simplicity
      makerTraits: 0n,
    };

    return order;
  }

  private async getOrderHash(chain: string, order: Order): Promise<string> {
    const network = EVM_NETWORKS[chain];
    const wallet = createEvmWallet(network);
    const lopAddress = getContractAddress(chain, 'limitOrderProtocol');

    const orderHash = await wallet.getPublicClient().readContract({
      address: lopAddress as `0x${string}`,
      abi: LIMIT_ORDER_PROTOCOL_ABI,
      functionName: 'hashOrder',
      args: [order],
    });

    return orderHash as string;
  }

  private async signOrder(chain: string, order: Order): Promise<{r: string, vs: string}> {
    const network = EVM_NETWORKS[chain];
    const wallet = createEvmWallet(network);
    const orderHash = await this.getOrderHash(chain, order);

    // Sign the order hash
    const signature = await wallet.getWalletClient().signMessage({
      message: { raw: orderHash as `0x${string}` },
    });

    // Parse signature components
    const r = signature.slice(0, 66);
    const s = signature.slice(66, 130);
    const v = parseInt(signature.slice(130, 132), 16);
    
    // Create vs (compact signature format)
    const vs = (v === 28 ? '0x' : '0x1') + s.slice(2);

    return { r, vs };
  }

  private async executeEvmSwap(chain: string, order: Order, signature: {r: string, vs: string}): Promise<string> {
    const network = EVM_NETWORKS[chain];
    const wallet = createEvmWallet(network);
    const lopAddress = getContractAddress(chain, 'limitOrderProtocol');

    const receipt = await wallet.writeContract({
      address: lopAddress,
      abi: LIMIT_ORDER_PROTOCOL_ABI,
      functionName: 'fillOrderArgs',
      args: [
        order,
        signature.r,
        signature.vs,
        order.makingAmount,
        0n, // takerTraits
        '0x', // args
      ],
    });

    return receipt.transactionHash;
  }

  private async processSuiSwap(order: Order, orderHash: string, secret: string, amount: number): Promise<string> {
    const network = SUI_NETWORKS['sui-testnet'];
    const wallet = createSuiWallet(network);
    const packageId = getContractAddress('sui-testnet', 'packageId');
    const factoryAddress = getContractAddress('sui-testnet', 'escrowFactory');

    // Get USDC coins for the swap
    const coins = await wallet.getAllCoins();
    const usdcType = `${packageId}::mock_usdc::USDC`;
    const usdcCoins = coins.filter(coin => coin.coinType === usdcType);

    if (usdcCoins.length === 0) {
      throw new Error('No USDC coins found for swap');
    }

    const amountMicro = Math.floor(amount * Math.pow(10, DECIMALS.USDC));

    const tx = new Transaction();
    tx.setGasBudget(15000000);

    // Split coins for the swap
    const [swapCoin] = tx.splitCoins(tx.object(usdcCoins[0].coinObjectId), [tx.pure.u64(amountMicro)]);
    
    // Get SUI for safety deposit
    const [safetyDeposit] = tx.splitCoins(tx.gas, [tx.pure.u64(1000000)]); // 0.001 SUI

    // Process cross-chain order
    tx.moveCall({
      target: `${packageId}::interface::process_evm_to_sui_swap`,
      arguments: [
        tx.object('0x0'), // resolver (placeholder)
        tx.object(factoryAddress),
        // EVM order parameters
        tx.pure.u256(order.salt.toString()),
        tx.pure(Array.from(Buffer.from(order.maker.slice(2), 'hex'))),
        tx.pure(Array.from(Buffer.from(order.receiver.slice(2), 'hex'))),
        tx.pure(Array.from(Buffer.from(order.makerAsset.slice(2), 'hex'))),
        tx.pure(Array.from(Buffer.from(order.takerAsset.slice(2), 'hex'))),
        tx.pure.u256(order.makingAmount.toString()),
        tx.pure.u256(order.takingAmount.toString()),
        tx.pure.u256(order.makerTraits.toString()),
        // Cross-chain parameters
        tx.pure(Array.from(Buffer.from(orderHash.slice(2), 'hex'))),
        tx.pure(Array.from(Buffer.from('0'.repeat(64), 'hex'))), // signature_r
        tx.pure(Array.from(Buffer.from('0'.repeat(64), 'hex'))), // signature_vs
        tx.pure.u256('11155111'), // evm_chain_id (Sepolia)
        tx.pure.u256('1'), // sui_chain_id
        swapCoin,
        safetyDeposit,
      ],
      typeArguments: [usdcType],
    });

    const result = await wallet.signAndExecuteTransaction(tx);
    
    if (result.effects?.status?.status !== 'success') {
      throw new Error('SUI swap transaction failed');
    }

    return result.digest;
  }
}

export const swapEngine = new SwapEngine();
