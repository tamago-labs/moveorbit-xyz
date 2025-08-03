// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import "../src/LimitOrderProtocol.sol";

/**
 * @title DeployLOP
 * @notice Deploy DeployLOP to multiple testnets (Ethereum Sepolia, Avalanche Fuji, Arbitrum Sepolia)
 * @dev Usage: 
 *   forge script script/DeployLOP.s.sol --rpc-url $ETHEREUM_SEPOLIA_RPC_URL --broadcast --verify
 *   forge script script/DeployLOP.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify
 *   forge script script/DeployLOP.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployLOP is Script {
    
    function run() external {
        string memory privateKeyString = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;
        
        // Handle private key with or without 0x prefix
        if (bytes(privateKeyString)[0] == '0' && bytes(privateKeyString)[1] == 'x') {
            deployerPrivateKey = vm.parseUint(privateKeyString);
        } else {
            deployerPrivateKey = vm.parseUint(string(abi.encodePacked("0x", privateKeyString)));
        }
        
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("===========================================");
        console.log("Deploying DeployLOP to testnet");
        console.log("===========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", deployer);
        console.log("Block number:", block.number); 
        
        // Check deployer balance
        uint256 balance = deployer.balance;
        console.log("Deployer balance:", balance / 1e18, "ETH");
        require(balance > 0.01 ether, "Insufficient balance for deployment");
        
        // Start broadcasting transactions to the real testnet
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy LOP
        LimitOrderProtocol lop = new LimitOrderProtocol();
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        console.log("LOP deployed successfully!");
        console.log("Contract address:", address(lop)); 
        
        // Print environment variable for this chain
        _printEnvironmentVariable(address(lop));
    }
    
    function _printEnvironmentVariable(address lop) internal view {
        console.log("\n===========================================");
        console.log("Environment Variable for .env file:");
        console.log("===========================================");
        
        string memory envVar;
        if (block.chainid == 11155111) {
            envVar = "ETH_SEPOLIA_USDC_ADDRESS";
        } else if (block.chainid == 43113) {
            envVar = "AVALANCHE_FUJI_USDC_ADDRESS";
        } else if (block.chainid == 421614) {
            envVar = "ARBITRUM_SEPOLIA_USDC_ADDRESS";
        } else {
            envVar = "UNKNOWN_CHAIN_USDC_ADDRESS";
        }
        
        console.log(string.concat("export ", envVar, "=", vm.toString(lop)));
        console.log("\n# Add this to your .env file");
        console.log("# Then run the same command on other chains:");
        console.log("# forge script script/DeployLOP.s.sol --rpc-url $AVALANCHE_FUJI_RPC_URL --broadcast --verify");
        console.log("# forge script script/DeployLOP.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --broadcast --verify");
    }
}