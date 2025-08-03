export interface NetworkConfig {
  name: string;
  displayName: string;
  chainId: number;
  rpcUrl: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  blockExplorer: string;
}

export interface SuiNetworkConfig {
  name: string;
  displayName: string;
  rpcUrl: string;
  blockExplorer: string;
}

// Helper function to get RPC URL at runtime
function getRpcUrl(envVar: string, fallback: string): string {
  return process.env[envVar] || fallback;
}

// Functions that return network configs at runtime (after dotenv is loaded)
export function getEvmNetworks(): Record<string, NetworkConfig> {
  return {
    'eth-sepolia': {
      name: 'eth-sepolia',
      displayName: 'Ethereum Sepolia',
      chainId: 11155111,
      rpcUrl: getRpcUrl('ETHEREUM_SEPOLIA_RPC', 'https://rpc.sepolia.org'),
      nativeCurrency: {
        name: 'Ethereum',
        symbol: 'ETH',
        decimals: 18,
      },
      blockExplorer: 'https://sepolia.etherscan.io',
    },
    'avax-fuji': {
      name: 'avax-fuji',
      displayName: 'Avalanche Fuji',
      chainId: 43113,
      rpcUrl: getRpcUrl('AVALANCHE_FUJI_RPC', 'https://api.avax-test.network/ext/bc/C/rpc'),
      nativeCurrency: {
        name: 'Avalanche',
        symbol: 'AVAX',
        decimals: 18,
      },
      blockExplorer: 'https://testnet.snowtrace.io',
    },
    'arb-sepolia': {
      name: 'arb-sepolia',
      displayName: 'Arbitrum Sepolia',
      chainId: 421614,
      rpcUrl: getRpcUrl('ARBITRUM_SEPOLIA_RPC', 'https://sepolia-rollup.arbitrum.io/rpc'),
      nativeCurrency: {
        name: 'Ethereum',
        symbol: 'ETH',
        decimals: 18,
      },
      blockExplorer: 'https://sepolia.arbiscan.io',
    },
  };
}

export function getSuiNetworks(): Record<string, SuiNetworkConfig> {
  return {
    'sui-testnet': {
      name: 'sui-testnet',
      displayName: 'SUI Testnet',
      rpcUrl: getRpcUrl('SUI_TESTNET_RPC', 'https://fullnode.testnet.sui.io'),
      blockExplorer: 'https://testnet.suivision.xyz',
    },
  };
}

// Lazy getters that load at runtime
export const EVM_NETWORKS = new Proxy({} as Record<string, NetworkConfig>, {
  get(target, prop) {
    if (typeof prop === 'string') {
      const networks = getEvmNetworks();
      return networks[prop];
    }
    return undefined;
  },
  ownKeys() {
    return Object.keys(getEvmNetworks());
  },
  has(target, prop) {
    return typeof prop === 'string' && prop in getEvmNetworks();
  },
  getOwnPropertyDescriptor(target, prop) {
    if (typeof prop === 'string' && prop in getEvmNetworks()) {
      return {
        enumerable: true,
        configurable: true,
        value: getEvmNetworks()[prop],
      };
    }
    return undefined;
  },
});

export const SUI_NETWORKS = new Proxy({} as Record<string, SuiNetworkConfig>, {
  get(target, prop) {
    if (typeof prop === 'string') {
      const networks = getSuiNetworks();
      return networks[prop];
    }
    return undefined;
  },
  ownKeys() {
    return Object.keys(getSuiNetworks());
  },
  has(target, prop) {
    return typeof prop === 'string' && prop in getSuiNetworks();
  },
  getOwnPropertyDescriptor(target, prop) {
    if (typeof prop === 'string' && prop in getSuiNetworks()) {
      return {
        enumerable: true,
        configurable: true,
        value: getSuiNetworks()[prop],
      };
    }
    return undefined;
  },
});

export const ALL_NETWORKS = new Proxy({} as Record<string, NetworkConfig | SuiNetworkConfig>, {
  get(target, prop) {
    if (typeof prop === 'string') {
      const evmNetworks = getEvmNetworks();
      const suiNetworks = getSuiNetworks();
      return evmNetworks[prop] || suiNetworks[prop];
    }
    return undefined;
  },
  ownKeys() {
    return [...Object.keys(getEvmNetworks()), ...Object.keys(getSuiNetworks())];
  },
  has(target, prop) {
    if (typeof prop === 'string') {
      const evmNetworks = getEvmNetworks();
      const suiNetworks = getSuiNetworks();
      return prop in evmNetworks || prop in suiNetworks;
    }
    return false;
  },
});

export const SUPPORTED_CHAINS = [
  'eth-sepolia',
  'avax-fuji', 
  'arb-sepolia',
  'sui-testnet',
] as const;

export type SupportedChain = typeof SUPPORTED_CHAINS[number];

export function getNetworkConfig(chain: SupportedChain): NetworkConfig | SuiNetworkConfig {
  const evmNetworks = getEvmNetworks();
  const suiNetworks = getSuiNetworks();
  return evmNetworks[chain] || suiNetworks[chain];
}

export function isEvmChain(chain: SupportedChain): chain is keyof ReturnType<typeof getEvmNetworks> {
  return chain in getEvmNetworks();
}

export function isSuiChain(chain: SupportedChain): chain is keyof ReturnType<typeof getSuiNetworks> {
  return chain in getSuiNetworks();
}
