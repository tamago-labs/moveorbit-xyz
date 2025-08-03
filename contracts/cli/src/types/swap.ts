export interface SwapOrder {
  salt: bigint;
  maker: string;
  receiver: string;
  makerAsset: string;
  takerAsset: string;
  makingAmount: bigint;
  takingAmount: bigint;
  makerTraits: bigint;
}

export interface SwapSignature {
  r: string;
  vs: string;
}

export interface SwapParams {
  fromChain: string;
  toChain: string;
  amount: number;
  resolverAddress?: string;
}

export interface SwapResult {
  success: boolean;
  txHash?: string;
  orderHash?: string;
  error?: string;
}

export interface CrossChainSwapData {
  orderHash: string;
  secret: string;
  secretHash: string;
  fromChain: string;
  toChain: string;
  amount: number;
  timestamp: number;
  status: 'pending' | 'processing' | 'completed' | 'failed';
}
