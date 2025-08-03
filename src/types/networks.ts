export interface NetworkInfo {
  name: string;
  displayName: string;
  chainId?: number;
  rpcUrl: string;
  blockExplorer: string;
  nativeCurrency?: {
    name: string;
    symbol: string;
    decimals: number;
  };
}

export interface TokenInfo {
  symbol: string;
  decimals: number;
  address?: string;
  coinType?: string;
}

export interface ChainBalance {
  chain: string;
  address: string;
  native: {
    symbol: string;
    balance: string;
    raw: string;
  };
  tokens: {
    [symbol: string]: {
      balance: string;
      raw: string;
    };
  };
}
