// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import { EscrowFactory } from "../src/EscrowFactory.sol";
import { Resolver } from "../src/Resolver.sol";
import { LimitOrderProtocol } from "../src/LimitOrderProtocol.sol"; // For interface typing only
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployFactoryAndResolver is Script {
    function run() external {
        uint256 deployerPrivateKey = _getDeployerKey();
        address resolverOwner = vm.addr(deployerPrivateKey);

        // Load pre-deployed LimitOrderProtocol address from env
        address lopAddress = vm.envAddress("LIMIT_ORDER_PROTOCOL_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy EscrowFactory
        EscrowFactory factory = new EscrowFactory(
            lopAddress,
            IERC20(address(0)),     // No fee token
            IERC20(address(0)),     // No access token
            resolverOwner,
            1 hours,
            1 hours
        );

        // Deploy Resolver
        Resolver resolver = new Resolver(factory, LimitOrderProtocol(lopAddress), resolverOwner);

        vm.stopBroadcast();

        // Log results
        console.log("EscrowFactory deployed at:", address(factory));
        console.log("Resolver deployed at:", address(resolver));
    }

    function _getDeployerKey() internal view returns (uint256) {
        string memory privateKeyString = vm.envString("PRIVATE_KEY");
        if (bytes(privateKeyString)[0] == '0' && bytes(privateKeyString)[1] == 'x') {
            return vm.parseUint(privateKeyString);
        } else {
            return vm.parseUint(string(abi.encodePacked("0x", privateKeyString)));
        }
    }
}
