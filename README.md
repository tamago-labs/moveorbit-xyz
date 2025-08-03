# MoveOrbit

*Extension to 1inch Fusion+ for Move-based blockchains, specifically Aptos and Sui built at ETHGlobal Unite DeFi Hackathon*

During the hackathon, we tried many different approaches and APIs to set up cross-chain swaps using the original contracts and system. After some trial and error, we found that the existing setup was too complex for quick testing and development.

We then decided to fork the protocol and build a simpler version. This allowed us to deploy on testnets and focus on core functionality. We also didn’t have time to complete the UI, but at least we have a functional CLI to interact with the system.

## Features

- **CLI with Interactive Menu:** Easy-to-use interface for all operations
- **Multi-Chain Support:** Ethereum Sepolia, Avalanche Fuji, Arbitrum Sepolia, SUI Testnet, Aptos Testnet
- **Mock USDC:** Includes mock USDC for both EVM and MoveVM; anyone can mint through the CLI
- **Cross-Chain Swaps:** Execute atomic swaps between EVM and SUI
- **Single Resolver:** Currently supports a single resolver only

## Multi-VM Resolver Extension

To support cross-chain atomic swaps across different virtual machines (EVM, SuiVM, and AptosVM), we created the `MultiVMResolverExtension`. This extension allows resolvers to register addresses across multiple chains  without modifying core escrow or limit order contracts. It cleanly integrates with 1inch’s Fusion+ architecture by overriding `_postInteraction`, enabling cross-VM logic while remaining modular and composable.

When a swap is executed, the extension parses `extraData` to determine the destination VM, chain ID, and recipient address. If the destination is a non-EVM chain, it creates a `CrossVMOrder` with metadata that off-chain agents or other contracts can process. This design makes it easy to trace and complete cross-chain transactions using external systems or dashboards.

## **Current Flow**

### **Resolver Setup & Registration**

1. **Deploy Contracts**
   ```solidity
   // Deploy core contracts
   LimitOrderProtocol lop = new LimitOrderProtocol();
   EscrowFactory factory = new EscrowFactory(lop, feeToken, accessToken, owner, rescueDelay, rescueDelay);
   Resolver resolver = new Resolver(lop, factory, resolverOwner);
   ```

2. **Register Multi-VM Resolver**
   ```solidity
   uint8[] memory vmTypes = [0, 1, 2]; // EVM, SUI, APTOS
   string[] memory addresses = [evmAddress, suiAddress, aptosAddress];
   resolver.registerResolver(vmTypes, addresses);
   ```

### **User Order Creation & Secret Sharing**

3. **User Creates Order**
   ```solidity
   IOrderMixin.Order memory order = IOrderMixin.Order({
       salt: nonce,
       maker: userAddress,
       receiver: userAddress,
       makerAsset: sourceToken,
       takerAsset: destinationToken,
       makingAmount: sourceAmount,
       takingAmount: destinationAmount,
       makerTraits: 0
   });
   ```

4. **User Signs Order (EIP-712)**
   ```solidity
   bytes32 orderHash = limitOrderProtocol.hashOrder(order);
   (uint8 v, bytes32 r, bytes32 s) = sign(userPrivateKey, orderHash);
   bytes32 vs = bytes32(uint256(v - 27) << 255) | s;
   ```

5. **User Shares Secret with Resolver (Off-chain)**
   ```solidity
   bytes32 secret = keccak256("user_secret");
   bytes32 secretHash = keccak256(abi.encodePacked(secret));
   
   // Resolver stores secret off-chain
   resolver.submitOrderAndSecret(orderHash, secretHash, secret);
   ```

6. **Resolver Processes Swap (EVM <> SUI/APTOS)**
   ```solidity
   resolver.processSwap(
       order,
       r, vs,
       1, // dstVM (1=SUI, 2=APTOS)
       suiChainId,
       "0x...suiAddress"
   );
   ```


## Getting Started

### **Prerequisites**
- Node.js 18+
- Foundry, SUI CLI, Aptos CLI

### 1. Install Dependencies
```bash
git clone https://github.com/tamago-labs/moveorbit-xyz
cd moveorbit-xyz
npm install
```

### 2. Configure Environment
```bash
cp .env.example .env
```

Edit `.env` and add your private keys:
```bash
# Private Keys (Required)
USER_SUI_PRIVATE_KEY=
USER_EVM_PRIVATE_KEY=
RESOLVER_SUI_PRIVATE_KEY=
RESOLVER_EVM_PRIVATE_KEY=

# RPC URLs
ETHEREUM_SEPOLIA_RPC=
AVALANCHE_FUJI_RPC=
ARBITRUM_SEPOLIA_RPC=
SUI_TESTNET_RPC=
```

### 3. (Optional) Run Tests

for EVM

```
cd contracts/evm
yarn install
forge build
forge test
```

For SUI

```
cd contracts/sui
sui move build
sui move test
```

For Aptos

```
cd contracts/aptos
aptos move build
aptos move test
```

### 4. Run CLI

Navigate back to the root then

```
npm run dev
```

## Screenshots

<img width="1294" height="467" alt="Screenshot from 2025-08-03 22-23-26" src="https://github.com/user-attachments/assets/65234f74-5a84-4299-95e2-0cb1d8c828ae" />

<img width="1380" height="623" alt="Screenshot from 2025-08-04 00-03-37" src="https://github.com/user-attachments/assets/4157bb23-798d-4325-8e04-f2bc1449ef5a" />


## Deployments

### Ethereum Sepolia

| Contract            | Address                                      |
|---------------------|----------------------------------------------|
| MockUSDC            | `0xAF4E836b7a1f20F1519cc82529Db54c62b02E93c` |
| LimitOrderProtocol  | `0x0d249716de3bE97a865Ff386Aa8A42428CB97347` |
| EscrowFactory       | `0x9304F30b1AEfeCB43F86fd5841C6ea75BD0F2529` |
| EscrowSrc           | `0x12ED717099C8bEfB6aaD60Da0FB13C945Fe770e0` |
| EscrowDst           | `0xEBD8929a2B50F0b92ee8caC4988C98fC49EC2ebC` |
| Resolver            | `0x6ee904a0Ff97b5682E80660Bf2Aca280D18aB5F3` |

---

### Avalanche Fuji

| Contract            | Address                                      |
|---------------------|----------------------------------------------|
| MockUSDC            | `0x959C3Bcf9AedF4c22061d8f935C477D9E47f02CA` |
| LimitOrderProtocol  | `0xdeA78063434EdCc56a58B52149d66A283FE0021C` |
| EscrowFactory       | `0x681f60a2E07Bf4d6b8AE429E6Af3dF3CA18654F2` |
| EscrowSrc           | `0x63F31AEFd98801A553c1eFCe8aEBaeb73F8094D3` |
| EscrowDst           | `0x52417373805c6E284107D03603FBdB9c577c377e` |
| Resolver            | `0xE88CF1EF7F929e9e22Ed058B0e4453A9BA9709b8` |

---

### Arbitrum Sepolia

| Contract            | Address                                      |
|---------------------|----------------------------------------------|
| MockUSDC            | `0x5F7392Ec616F829Ab54092e7F167F518835Ac740` |
| LimitOrderProtocol  | `0xCeB75a9a4Af613afd42BD000893eD16fB1F0F057` |
| EscrowFactory       | `0xF0b8eaEeBe416Ec43f79b0c83CCc5670d2b7C3Db` |
| EscrowSrc           | `0x6Ab31A722D4dB2b540D76e8354438366efda8693` |
| EscrowDst           | `0x06BC3280fBc8993ba5F7F65b82bF811D1Ac08740` |
| Resolver            | `0xe03dFA1B78e5A25a06b67C73f32f3C8739ADba7c` |

---

### Sui Testnet

| Contract Name             | Address                                                              |
|---------------------------|----------------------------------------------------------------------|
| PackageID                 | `0x6d956f92fd7c8a791643df6b6a7e0cb78b94d36524a99822a2ef2ac0f2227aaa` |
| mock_usdc::USDCGlobal     | `0x5ba29a4014f08697d2045e2e7a62be3f06314694779d7bab2fea023ab086c188` |
| escrow_factory::ResolverRegistry | `0x4fc09dac9213bdc785015d167de81ffc34a23a419721e555a4624ed16d2c1bc5` |
| escrow_factory::EscrowFactory | `0xf29bea78c3b4f6b1c0cea9d85ffa6b080863c0c2a064fe7a6e59c945da742d09` |

---

### Aptos

Aptos contracts are not yet deployed.


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
