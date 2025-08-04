// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import { Resolver } from "../src/Resolver.sol";
import { IEscrowFactory } from "cross-chain-swap/interfaces/IEscrowFactory.sol";
import { IOrderMixin } from "../src/interfaces/IOrderMixin.sol";

contract DeployResolver is Script {
    function run() external {
        string memory privateKeyString = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        
        // Handle private key with or without 0x prefix
        if (bytes(privateKeyString)[0] == '0' && bytes(privateKeyString)[1] == 'x') {
            deployerPrivateKey = vm.parseUint(privateKeyString);
        } else {
            deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyString)));
        }
        
        address resolverOwner = vm.addr(deployerPrivateKey);

        // Load pre-deployed addresses
        address factoryAddress = vm.envAddress("ESCROW_FACTORY_ADDRESS");
        address lopAddress = vm.envAddress("LIMIT_ORDER_PROTOCOL_ADDRESS");

        console.log("Deploying Resolver with:");
        console.log("  Factory:", factoryAddress);
        console.log("  LOP:", lopAddress);
        console.log("  Owner:", resolverOwner);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new Resolver with fixed cross-chain logic
        Resolver resolver = new Resolver(
            IEscrowFactory(factoryAddress), 
            IOrderMixin(lopAddress), 
            resolverOwner
        );

        vm.stopBroadcast();

        // Log results
        console.log("");
        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("New Resolver deployed at:", address(resolver));
        console.log("");
        console.log("Next steps:");
        console.log("1. Update your .env with RESOLVER_ADDRESS=", vm.toString(address(resolver)));
        console.log("2. Test the cross-chain swap with the CLI");
        console.log("3. User tokens will now be LOCKED (not immediately swapped!)");
    }
}
