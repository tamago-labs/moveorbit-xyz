# MoveOrbit

*Extension to 1inch Fusion+ for Move-based blockchains, specifically Aptos and Sui built at ETHGlobal Unite DeFi Hackathon*

During the hackathon, we went through trial and error trying out APIs and using the main contract settings. 

However, we realized that we needed to simplify cross-chain swaps by forking and creating a simplified version of the Limit Order Protocol, which we successfully deployed to testnets for quicker development.

We also didn’t have time to complete the UI, but at least we have a functional CLI to interact with the system.

## Features

- **CLI with Interactive Menu:** Easy-to-use interface for all operations
- **Multi-Chain Support:** Ethereum Sepolia, Avalanche Fuji, Arbitrum Sepolia, SUI Testnet, Aptos Testnet
- **Mock USDC:** Includes mock USDC for both EVM and MoveVM; anyone can mint through the CLI
- **Cross-Chain Swaps:** Execute atomic swaps between EVM and SUI
- **Single Resolver:** Currently supports a single resolver only
