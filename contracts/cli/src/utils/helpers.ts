import { formatUnits, parseUnits } from 'viem';
import { DECIMALS } from '../config/constants';

export function formatTokenAmount(amount: bigint | string, decimals: number = DECIMALS.USDC): string {
  const amountBigInt = typeof amount === 'string' ? BigInt(amount) : amount;
  return formatUnits(amountBigInt, decimals);
}

export function parseTokenAmount(amount: string, decimals: number = DECIMALS.USDC): bigint {
  return parseUnits(amount, decimals);
}

export function shortenAddress(address: string, chars: number = 4): string {
  if (address.length <= chars * 2 + 2) return address;
  return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
}

export function shortenTxHash(hash: string, chars: number = 6): string {
  if (hash.length <= chars * 2 + 2) return hash;
  return `${hash.slice(0, chars + 2)}...${hash.slice(-chars)}`;
}

export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

export function isValidAddress(address: string, type: 'evm' | 'sui'): boolean {
  if (type === 'evm') {
    return /^0x[a-fA-F0-9]{40}$/.test(address);
  } else if (type === 'sui') {
    return /^0x[a-fA-F0-9]{64}$/.test(address);
  }
  return false;
}

export function getCurrentTimestamp(): number {
  return Math.floor(Date.now() / 1000);
}

export function formatTimestamp(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleString();
}

export function generateRandomHex(length: number): string {
  const chars = '0123456789abcdef';
  let result = '0x';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export function validatePrivateKey(privateKey: string): boolean {
  const cleanKey = privateKey.startsWith('0x') ? privateKey.slice(2) : privateKey;
  return /^[a-fA-F0-9]{64}$/.test(cleanKey);
}

export function createProgressBar(current: number, total: number, width: number = 30): string {
  const percentage = Math.min(current / total, 1);
  const filled = Math.floor(percentage * width);
  const empty = width - filled;
  
  return `[${'█'.repeat(filled)}${' '.repeat(empty)}] ${Math.round(percentage * 100)}%`;
}
