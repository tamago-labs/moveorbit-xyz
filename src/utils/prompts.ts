import prompts from 'prompts';
import { SupportedChain } from '../config/networks';

export async function selectChain(
  message: string, 
  chains: SupportedChain[], 
  excludeChain?: SupportedChain
): Promise<SupportedChain> {
  const availableChains = excludeChain 
    ? chains.filter(chain => chain !== excludeChain)
    : chains;

  const response = await prompts({
    type: 'select',
    name: 'chain',
    message,
    choices: availableChains.map(chain => ({
      title: getChainDisplayName(chain),
      value: chain,
    })),
  });

  if (!response.chain) {
    process.exit(0);
  }

  return response.chain;
}

export async function inputAmount(message: string = 'Enter amount'): Promise<number> {
  const response = await prompts({
    type: 'number',
    name: 'amount',
    message,
    validate: (value: number) => {
      if (!value || value <= 0) {
        return 'Amount must be greater than 0';
      }
      if (value > 10000) {
        return 'Amount cannot exceed 10,000 USDC';
      }
      return true;
    },
  });

  if (response.amount === undefined) {
    process.exit(0);
  }

  return response.amount;
}

export async function confirmSwap(
  fromChain: SupportedChain,
  toChain: SupportedChain,
  amount: number
): Promise<boolean> {
  const response = await prompts({
    type: 'confirm',
    name: 'confirmed',
    message: `Confirm swap: ${amount} USDC from ${getChainDisplayName(fromChain)} to ${getChainDisplayName(toChain)}?`,
    initial: true,
  });

  return response.confirmed ?? false;
}

export async function inputResolverAddress(): Promise<string | undefined> {
  const response = await prompts({
    type: 'text',
    name: 'resolver',
    message: 'Enter SUI resolver address (optional):',
    validate: (value: string) => {
      if (!value) return true; // Optional
      if (!value.startsWith('0x') || value.length !== 66) {
        return 'Invalid SUI address format';
      }
      return true;
    },
  });

  return response.resolver || undefined;
}

export async function selectAction(): Promise<'balance' | 'mint' | 'swap' | 'setup' | 'quick-setup' | 'exit'> {
  const response = await prompts({
    type: 'select',
    name: 'action',
    message: 'What would you like to do?',
    choices: [
      { title: '💰 Check Balances', value: 'balance' },
      { title: '🪙 Mint USDC', value: 'mint' },
      { title: '🔄 Cross-Chain Swap', value: 'swap' },
      { title: '⚡ Quick Setup - Start testing immediately', value: 'quick-setup' },
      { title: '⚙️ Advanced Setup - Full resolver configuration', value: 'setup' },
      { title: '❌ Exit', value: 'exit' },
    ],
  });

  if (!response.action) {
    process.exit(0);
  }

  return response.action;
}

export async function waitForEnter(message: string = 'Press Enter to continue...'): Promise<void> {
  await prompts({
    type: 'text',
    name: 'continue',
    message,
    initial: '',
  });
}

function getChainDisplayName(chain: SupportedChain): string {
  const displayNames: Record<SupportedChain, string> = {
    'eth-sepolia': '🔵 Ethereum Sepolia',
    'avax-fuji': '🔴 Avalanche Fuji',
    'arb-sepolia': '🔷 Arbitrum Sepolia',
    'sui-testnet': '🟦 SUI Testnet',
  };

  return displayNames[chain] || chain;
}

export function formatProgress(current: number, total: number): string {
  const percentage = Math.round((current / total) * 100);
  const filled = Math.round((current / total) * 20);
  const empty = 20 - filled;
  
  return `[${'█'.repeat(filled)}${' '.repeat(empty)}] ${percentage}%`;
}

export function displayWelcome(): void {
  console.log(`
╔══════════════════════════════════════════════════════════════╗
║                      🌉 MoveOrbit CLI                       ║
║                Cross-Chain Swap Protocol                    ║
╚══════════════════════════════════════════════════════════════╝

Welcome to MoveOrbit! Seamlessly swap tokens between EVM and SUI chains.

Supported Networks:
🔵 Ethereum Sepolia  🔴 Avalanche Fuji  🔷 Arbitrum Sepolia  🟦 SUI Testnet
  `);
}

export function displaySwapSummary(
  fromChain: SupportedChain,
  toChain: SupportedChain,
  amount: number,
  txHash?: string
): void {
  console.log(`
╔══════════════════════════════════════════════════════════════╗
║                      Swap Summary                            ║
╠══════════════════════════════════════════════════════════════╣
║ From:     ${getChainDisplayName(fromChain).padEnd(46)} ║
║ To:       ${getChainDisplayName(toChain).padEnd(46)} ║
║ Amount:   ${`${amount} USDC`.padEnd(46)} ║
${txHash ? `║ TX Hash:  ${txHash.slice(0, 46)}... ║` : ''}
╚══════════════════════════════════════════════════════════════╝
  `);
}
