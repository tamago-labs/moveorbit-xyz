import { SupportedChain } from './networks';

export interface ContractAddresses {
  mockUSDC: string;
  limitOrderProtocol?: string;
  escrowFactory?: string;
  escrowSrc?: string;
  escrowDst?: string;
  resolver?: string;
  resolverRegistry?: string;
  packageId?: string;
  usdcGlobal?: string;
}

export const CONTRACT_ADDRESSES: Record<SupportedChain, ContractAddresses> = {
  'eth-sepolia': {
    mockUSDC: '0xAF4E836b7a1f20F1519cc82529Db54c62b02E93c',
    limitOrderProtocol: '0x0d249716de3bE97a865Ff386Aa8A42428CB97347',
    escrowFactory: '0x9304F30b1AEfeCB43F86fd5841C6ea75BD0F2529',
    escrowSrc: '0x12ED717099C8bEfB6aaD60Da0FB13C945Fe770e0',
    escrowDst: '0xEBD8929a2B50F0b92ee8caC4988C98fC49EC2ebC',
    resolver: '0x6ee904a0Ff97b5682E80660Bf2Aca280D18aB5F3',
  },
  'avax-fuji': {
    mockUSDC: '0x959C3Bcf9AedF4c22061d8f935C477D9E47f02CA',
    limitOrderProtocol: '0xdeA78063434EdCc56a58B52149d66A283FE0021C',
    escrowFactory: '0x681f60a2E07Bf4d6b8AE429E6Af3dF3CA18654F2',
    escrowSrc: '0x63F31AEFd98801A553c1eFCe8aEBaeb73F8094D3',
    escrowDst: '0x52417373805c6E284107D03603FBdB9c577c377e',
    resolver: '0xE88CF1EF7F929e9e22Ed058B0e4453A9BA9709b8',
  },
  'arb-sepolia': {
    mockUSDC: '0x5F7392Ec616F829Ab54092e7F167F518835Ac740',
    limitOrderProtocol: '0xCeB75a9a4Af613afd42BD000893eD16fB1F0F057',
    escrowFactory: '0xF0b8eaEeBe416Ec43f79b0c83CCc5670d2b7C3Db',
    escrowSrc: '0x6Ab31A722D4dB2b540D76e8354438366efda8693',
    escrowDst: '0x06BC3280fBc8993ba5F7F65b82bF811D1Ac08740',
    resolver: '0xe03dFA1B78e5A25a06b67C73f32f3C8739ADba7c',
  },
  'sui-testnet': {
    mockUSDC: '', // SUI uses different token structure
    packageId: '0x6d956f92fd7c8a791643df6b6a7e0cb78b94d36524a99822a2ef2ac0f2227aaa',
    usdcGlobal: '0x5ba29a4014f08697d2045e2e7a62be3f06314694779d7bab2fea023ab086c188',
    resolverRegistry: '0x4fc09dac9213bdc785015d167de81ffc34a23a419721e555a4624ed16d2c1bc5',
    escrowFactory: '0xf29bea78c3b4f6b1c0cea9d85ffa6b080863c0c2a064fe7a6e59c945da742d09',
  },
};

// ERC20 ABI for MockUSDC
export const MOCK_USDC_ABI = [
  {
    "inputs": [{"internalType": "address", "name": "to", "type": "address"}, {"internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "mint",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "spender", "type": "address"}, {"internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "approve",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "to", "type": "address"}, {"internalType": "uint256", "name": "amount", "type": "uint256"}],
    "name": "transfer",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "account", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "owner", "type": "address"}, {"internalType": "address", "name": "spender", "type": "address"}],
    "name": "allowance",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "decimals",
    "outputs": [{"internalType": "uint8", "name": "", "type": "uint8"}],
    "stateMutability": "view",
    "type": "function"
  }
] as const;

// LimitOrderProtocol ABI (simplified)
export const LIMIT_ORDER_PROTOCOL_ABI = [
  {
    "inputs": [
      {
        "components": [
          {"internalType": "uint256", "name": "salt", "type": "uint256"},
          {"internalType": "address", "name": "maker", "type": "address"},
          {"internalType": "address", "name": "receiver", "type": "address"},
          {"internalType": "address", "name": "makerAsset", "type": "address"},
          {"internalType": "address", "name": "takerAsset", "type": "address"},
          {"internalType": "uint256", "name": "makingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "takingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "makerTraits", "type": "uint256"}
        ],
        "internalType": "struct IOrderMixin.Order",
        "name": "order",
        "type": "tuple"
      }
    ],
    "name": "hashOrder",
    "outputs": [{"internalType": "bytes32", "name": "orderHash", "type": "bytes32"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {
        "components": [
          {"internalType": "uint256", "name": "salt", "type": "uint256"},
          {"internalType": "address", "name": "maker", "type": "address"},
          {"internalType": "address", "name": "receiver", "type": "address"},
          {"internalType": "address", "name": "makerAsset", "type": "address"},
          {"internalType": "address", "name": "takerAsset", "type": "address"},
          {"internalType": "uint256", "name": "makingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "takingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "makerTraits", "type": "uint256"}
        ],
        "internalType": "struct IOrderMixin.Order",
        "name": "order",
        "type": "tuple"
      },
      {"internalType": "bytes32", "name": "r", "type": "bytes32"},
      {"internalType": "bytes32", "name": "vs", "type": "bytes32"},
      {"internalType": "uint256", "name": "amount", "type": "uint256"},
      {"internalType": "uint256", "name": "takerTraits", "type": "uint256"},
      {"internalType": "bytes", "name": "args", "type": "bytes"}
    ],
    "name": "fillOrderArgs",
    "outputs": [
      {"internalType": "uint256", "name": "makingAmount", "type": "uint256"},
      {"internalType": "uint256", "name": "takingAmount", "type": "uint256"},
      {"internalType": "bytes32", "name": "orderHash", "type": "bytes32"}
    ],
    "stateMutability": "payable",
    "type": "function"
  }
] as const;

// Resolver ABI for cross-chain operations
export const RESOLVER_ABI = [
  {
    "inputs": [
      {
        "components": [
          {"internalType": "uint256", "name": "salt", "type": "uint256"},
          {"internalType": "address", "name": "maker", "type": "address"},
          {"internalType": "address", "name": "receiver", "type": "address"},
          {"internalType": "address", "name": "makerAsset", "type": "address"},
          {"internalType": "address", "name": "takerAsset", "type": "address"},
          {"internalType": "uint256", "name": "makingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "takingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "makerTraits", "type": "uint256"}
        ],
        "internalType": "struct IOrderMixin.Order",
        "name": "order",
        "type": "tuple"
      },
      {"internalType": "bytes32", "name": "r", "type": "bytes32"},
      {"internalType": "bytes32", "name": "vs", "type": "bytes32"}
    ],
    "name": "processSimpleSwap",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "components": [
          {"internalType": "uint256", "name": "salt", "type": "uint256"},
          {"internalType": "address", "name": "maker", "type": "address"},
          {"internalType": "address", "name": "receiver", "type": "address"},
          {"internalType": "address", "name": "makerAsset", "type": "address"},
          {"internalType": "address", "name": "takerAsset", "type": "address"},
          {"internalType": "uint256", "name": "makingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "takingAmount", "type": "uint256"},
          {"internalType": "uint256", "name": "makerTraits", "type": "uint256"}
        ],
        "internalType": "struct IOrderMixin.Order",
        "name": "order",
        "type": "tuple"
      },
      {"internalType": "bytes32", "name": "r", "type": "bytes32"},
      {"internalType": "bytes32", "name": "vs", "type": "bytes32"},
      {"internalType": "uint8", "name": "dstVM", "type": "uint8"},
      {"internalType": "uint256", "name": "dstChainId", "type": "uint256"},
      {"internalType": "string", "name": "dstAddress", "type": "string"}
    ],
    "name": "processSwap",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "bytes32", "name": "orderHash", "type": "bytes32"},
      {"internalType": "bytes32", "name": "secretHash", "type": "bytes32"},
      {"internalType": "bytes32", "name": "secret", "type": "bytes32"}
    ],
    "name": "submitOrderAndSecret",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
] as const;

export function getContractAddress(chain: SupportedChain, contract: keyof ContractAddresses): string {
  const address = CONTRACT_ADDRESSES[chain][contract];
  if (!address) {
    throw new Error(`Contract ${contract} not found on ${chain}`);
  }
  return address;
}
