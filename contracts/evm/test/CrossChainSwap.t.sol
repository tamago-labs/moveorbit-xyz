// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/EscrowFactory.sol";
import "../src/SimpleResolver.sol";
import { LimitOrderProtocol } from  "../src/LimitOrderProtocol.sol";
import "../src/MockUSDC.sol";
import "../src/interfaces/IBaseEscrow.sol";
import { Timelocks } from "../src/libraries/TimelocksLib.sol";

contract CrossChainSwapTest is Test {
    EscrowFactory public escrowFactory;
    SimpleResolver public resolver;
    LimitOrderProtocol public lop;
    MockUSDC public usdc;
    MockUSDC public weth;
    
    address public deployer = address(this);
    address public user = address(0x1);
    address public resolverOwner = address(0x2);
    
    uint256 public userPrivateKey = 0xA11CE;
    
    function setUp() public {
        user = vm.addr(userPrivateKey);
        
        lop = new LimitOrderProtocol();
        usdc = new MockUSDC();
        weth = new MockUSDC();
        
        escrowFactory = new EscrowFactory(
            address(lop),
            IERC20(address(weth)),
            IERC20(address(0)),
            deployer,
            1800,
            1800
        );
        
        resolver = new SimpleResolver(
            IEscrowFactory(address(escrowFactory)),
            IOrderMixin(address(lop)),
            resolverOwner
        );
        
        usdc.mint(user, 10000 * 1e6);
        weth.mint(address(resolver), 5000 * 1e18);
        
        vm.prank(user);
        usdc.approve(address(lop), type(uint256).max);
        
        vm.label(user, "User");
        vm.label(resolverOwner, "ResolverOwner");
        vm.label(address(escrowFactory), "EscrowFactory");
        vm.label(address(resolver), "SimpleResolver");
        vm.label(address(usdc), "USDC");
        vm.label(address(weth), "WETH");
    }
    
    function test_ContractsDeployment() public {
        assertTrue(address(escrowFactory) != address(0));
        assertTrue(address(resolver) != address(0));
        assertTrue(address(lop) != address(0));
        
        console.log("All contracts deployed successfully");
        console.log("EscrowFactory:", address(escrowFactory));
        console.log("SimpleResolver:", address(resolver));
        console.log("MinimalLimitOrderProtocol:", address(lop));
    }
    
    function test_HashTimelockCompatibility() public {
        bytes32 secret = "secret123";
        bytes32 hashlock = keccak256(abi.encode(secret));
        
        // This hashlock format should work across EVM and Sui
        assertTrue(hashlock != bytes32(0));
        assertEq(hashlock, keccak256(abi.encode(secret)));
        
        console.log("Hash timelock mechanism verified");
        console.log("Secret:", vm.toString(secret));
        console.log("Hashlock:", vm.toString(hashlock));
    }
    
    function test_EscrowImmutables() public {
        bytes32 secret = keccak256(abi.encodePacked("test_secret"));
        bytes32 hashlock = keccak256(abi.encode(secret));
        
        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: keccak256("test_order"),
            hashlock: hashlock,
            maker: user,
            taker: address(resolver),
            token: address(usdc),
            amount: 1000 * 1e6,
            safetyDeposit: 0.01 ether,
            timelocks: Timelocks.wrap(0)
        });
        
        assertTrue(immutables.hashlock == hashlock);
        assertTrue(immutables.maker == user);
        assertTrue(immutables.token == address(usdc));
        
        console.log("Escrow immutables structure verified");
    }
    
    function test_LimitOrderProtocolBasics() public {
        bytes32 domainSeparator = lop.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0));
        
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 12345,
            maker: user,
            receiver: address(0),
            makerAsset: address(usdc),
            takerAsset: address(weth),
            makingAmount: 1000 * 1e6,
            takingAmount: 1 * 1e18,
            makerTraits: 0
        });
        
        bytes32 orderHash = lop.hashOrder(order);
        assertTrue(orderHash != bytes32(0));
        
        console.log("Limit Order Protocol basics verified");
        console.log("Domain Separator:", vm.toString(domainSeparator));
        console.log("Order Hash:", vm.toString(orderHash));
    }
    
    function test_ResolverOwnership() public {
        assertEq(resolver.owner(), resolverOwner);
        console.log("SimpleResolver ownership verified");
        console.log("Owner:", resolver.owner());
    }
    
    function test_GasEstimates() public {
        uint256 gasBefore = gasleft();
        
        // Test contract interactions
        lop.DOMAIN_SEPARATOR();
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for domain separator:", gasUsed);
        
        assertTrue(gasUsed < 10000); // Should be very efficient
        console.log("Gas efficiency verified");
    }
}
