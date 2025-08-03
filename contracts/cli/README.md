# MoveOrbit CLI

Cross-chain token swap CLI for the MoveOrbit protocol. Enables seamless USDC transfers between EVM chains (Ethereum, Avalanche, Arbitrum) and SUI.

## Features

🔄 **Cross-Chain Swaps**: Transfer USDC between EVM ↔ SUI  
🏦 **Multi-Chain Support**: Ethereum Sepolia, Avalanche Fuji, Arbitrum Sepolia, SUI Testnet  
🔐 **Atomic Swaps**: Secret-based atomic completion  
⚡ **Interactive Mode**: User-friendly interactive interface  
🏗️ **Resolver Management**: Setup and manage cross-chain resolvers  

## Quick Start

### 1. Install Dependencies
```bash
npm install
```

### 2. Setup Environment
```bash
cp .env.example .env
# Edit .env with your private keys
```

### 3. Build the CLI
```bash
npm run build
```

### 4. Run Interactive Mode
```bash
npm run dev
# or
moveorbit
```

## Environment Setup

Create a `.env` file with your private keys:

```env
# Private Keys (NEVER commit these!)
SUI_PRIVATE_KEY=your_sui_private_key_here
EVM_PRIVATE_KEY=your_evm_private_key_here

# RPC URLs (optional - defaults provided)
ETHEREUM_SEPOLIA_RPC=https://rpc.sepolia.org
AVALANCHE_FUJI_RPC=https://api.avax-test.network/ext/bc/C/rpc
ARBITRUM_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
SUI_TESTNET_RPC=https://fullnode.testnet.sui.io
```

## Usage

### Interactive Mode (Recommended)
```bash
moveorbit
# or
moveorbit interactive
```

### Command Line Interface

#### Check Balances
```bash
moveorbit balance                    # All chains
moveorbit balance -c eth-sepolia     # Specific chain
moveorbit balance --verbose          # Detailed view
```

#### Account Information
```bash
moveorbit account                    # All accounts
moveorbit account -c sui-testnet     # Specific chain
```

#### Mint Tokens
```bash
moveorbit mint eth-sepolia 100       # Mint 100 USDC on Ethereum Sepolia
moveorbit mint sui-testnet 50        # Mint 50 USDC on SUI
moveorbit mint avax-fuji 200 --to 0x...  # Mint to specific address
```

#### Transfer Tokens
```bash
moveorbit transfer eth-sepolia 0x... 100  # Transfer 100 USDC
moveorbit transfer sui-testnet 0x... 50   # Transfer on SUI
```

#### Approve Contracts
```bash
moveorbit approve eth-sepolia 0x... 100   # Approve 100 USDC
moveorbit approve eth-sepolia 0x... max   # Approve maximum
```

#### Setup Resolvers
```bash
moveorbit setup-resolver             # Setup all resolvers
moveorbit setup-resolver -c sui-testnet  # Setup specific chain
```

#### Register Multi-VM Resolver
```bash
moveorbit register-multivm --sui-resolver 0x...
```

#### Cross-Chain Swaps
```bash
# Direct swap
moveorbit swap eth-sepolia sui-testnet 100 --resolver 0x...

# EVM to EVM (no resolver needed)
moveorbit swap eth-sepolia avax-fuji 100

# Interactive swap selection
moveorbit swap
```

#### Check Swap Status
```bash
moveorbit status                     # Show help
moveorbit status 0x...               # Check specific order
moveorbit status --all               # Show all tracked swaps
moveorbit status --all --verbose     # Detailed view
```

## Supported Networks

| Network | Chain ID | Testnet |
|---------|----------|---------|
| Ethereum Sepolia | 11155111 | ✅ |
| Avalanche Fuji | 43113 | ✅ |
| Arbitrum Sepolia | 421614 | ✅ |
| SUI Testnet | 1 | ✅ |

## Contract Addresses

### Ethereum Sepolia
- MockUSDC: `0xAF4E836b7a1f20F1519cc82529Db54c62b02E93c`
- LimitOrderProtocol: `0x0d249716de3bE97a865Ff386Aa8A42428CB97347`

### Avalanche Fuji
- MockUSDC: `0x959C3Bcf9AedF4c22061d8f935C477D9E47f02CA`
- LimitOrderProtocol: `0xdeA78063434EdCc56a58B52149d66A283FE0021C`

### Arbitrum Sepolia
- MockUSDC: `0x5F7392Ec616F829Ab54092e7F167F518835Ac740`
- LimitOrderProtocol: `0xCeB75a9a4Af613afd42BD000893eD16fB1F0F057`

### SUI Testnet
- Package ID: `0x6d956f92fd7c8a791643df6b6a7e0cb78b94d36524a99822a2ef2ac0f2227aaa`
- USDC Global: `0x5ba29a4014f08697d2045e2e7a62be3f06314694779d7bab2fea023ab086c188`
- Resolver Registry: `0x4fc09dac9213bdc785015d167de81ffc34a23a419721e555a4624ed16d2c1bc5`
- Escrow Factory: `0xf29bea78c3b4f6b1c0cea9d85ffa6b080863c0c2a064fe7a6e59c945da742d09`

## Workflow Examples

### 1. First Time Setup
```bash
# 1. Check your accounts
moveorbit account

# 2. Setup resolvers
moveorbit setup-resolver

# 3. Register multi-VM resolver
moveorbit register-multivm --sui-resolver 0x...

# 4. Check balances
moveorbit balance

# 5. Mint some tokens if needed
moveorbit mint eth-sepolia 1000
moveorbit mint sui-testnet 1000
```

### 2. Simple EVM to EVM Swap
```bash
# Check balances first
moveorbit balance

# Perform swap (no resolver needed)
moveorbit swap eth-sepolia avax-fuji 100

# Verify swap completed
moveorbit balance
```

### 3. Cross-Chain EVM to SUI Swap
```bash
# Ensure you have a SUI resolver address
moveorbit setup-resolver

# Perform cross-chain swap
moveorbit swap eth-sepolia sui-testnet 100 --resolver 0x...

# Check status
moveorbit status --all

# Verify balances
moveorbit balance
```

### 4. Interactive Session
```bash
# Start interactive mode
moveorbit

# Follow the prompts:
# 1. Select "Check Balances" to see current state
# 2. Select "Mint USDC" if you need test tokens
# 3. Select "Cross-Chain Swap" to transfer tokens
# 4. Select "Setup Resolvers" if needed
```

## Troubleshooting

### Common Issues

#### 1. "Private key not found"
- Ensure your `.env` file exists and contains valid private keys
- Check that private keys are properly formatted (64 hex characters)

#### 2. "Insufficient balance"
- Use `moveorbit mint <chain> <amount>` to get test tokens
- Check balances with `moveorbit balance`

#### 3. "Resolver address required"
- Cross-chain swaps to/from SUI require a resolver address
- Run `moveorbit setup-resolver` to create resolvers
- Use the returned SUI resolver address in swap commands

#### 4. "Transaction failed"
- Check your native token balance for gas fees
- Verify contract addresses are correct
- Ensure sufficient token approvals

#### 5. "RPC connection failed"
- Check your internet connection
- Verify RPC URLs in `.env` file
- Try using alternative RPC endpoints

### Getting Test Tokens

#### Native Tokens (for gas):
- **Ethereum Sepolia**: [Sepolia Faucet](https://sepoliafaucet.com/)
- **Avalanche Fuji**: [Fuji Faucet](https://faucet.avax.network/)
- **Arbitrum Sepolia**: [Arbitrum Faucet](https://faucet.arbitrum.io/)
- **SUI Testnet**: Built-in faucet (request via CLI)

#### MockUSDC Tokens:
```bash
moveorbit mint <chain> <amount>
```

## Development

### Project Structure
```
src/
├── commands/          # CLI commands
├── clients/           # Blockchain clients (EVM, SUI)
├── config/            # Network and contract configurations
├── services/          # Business logic (swaps, resolvers, secrets)
├── types/             # TypeScript type definitions
├── utils/             # Helper utilities
└── index.ts           # Main CLI entry point
```

### Adding New Commands
1. Create command file in `src/commands/`
2. Import and register in `src/index.ts`
3. Follow existing command patterns

### Adding New Networks
1. Update network configurations in `src/config/networks.ts`
2. Add contract addresses in `src/config/contracts.ts`
3. Update supported chains constant

## Security

⚠️ **Important Security Notes**:

- Never commit private keys to version control
- Use test networks only for development
- Keep your `.env` file secure and local
- Consider using hardware wallets for production
- Audit all transaction details before signing

## Support

- 📖 **Documentation**: Check the inline help with `moveorbit --help`
- 🐛 **Issues**: Report bugs or request features
- 💬 **Community**: Join our Discord for support

## License

MIT License - see LICENSE file for details.

---

Built with ❤️ for the MoveOrbit ecosystem
