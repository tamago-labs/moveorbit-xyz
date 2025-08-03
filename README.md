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


