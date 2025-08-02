// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { LimitOrderProtocol } from  "../src/LimitOrderProtocol.sol";
import { EscrowFactory } from "../src/EscrowFactory.sol";
import { Resolver } from  "../src/Resolver.sol";
import { MockUSDC } from "../src/MockUSDC.sol";

import {IOrderMixin} from "../src/interfaces/IOrderMixin.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MultiVMResolverExtension} from "../src/extensions/MultiVMResolverExtension.sol";

/**
 * @title Flow Tests
 * @notice Test the 3 main flows: EVM-to-EVM, EVM-to-SUI/APTOS, Multi-VM Resolver
 */
contract IntegrationTest is Test {
    
    // Core contracts
    LimitOrderProtocol public lop;
    EscrowFactory public factory;
    Resolver public resolver;
    
    // Test tokens
    MockUSDC public usdcSrc;
    MockUSDC public usdcDst;
    
    // Test accounts with deterministic private keys
    uint256 public userPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 public resolverPrivateKey = 0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd;
    
    address public user;
    address public resolverOwner;
    
    // Test constants
    uint256 public constant SWAP_AMOUNT = 1000 * 1e6; // 1000 USDC
    
    event SimpleSwapProcessed(bytes32 indexed orderHash, address indexed maker, address indexed taker);
    event CrossChainSwapProcessed(bytes32 indexed orderHash, Resolver.VMType dstVM, uint256 dstChainId, string dstAddress);
    event ResolverRegistered(uint8[] vmTypes, string[] addresses);
    event CrossVMOrderCreated(bytes32 indexed orderHash, address indexed resolver, MultiVMResolverExtension.VMType srcVM, MultiVMResolverExtension.VMType dstVM, uint256 srcChainId, uint256 dstChainId, string dstAddress);

    function setUp() public {
        // Create deterministic addresses
        user = vm.addr(userPrivateKey);
        resolverOwner = vm.addr(resolverPrivateKey);
        
        console.log("User address:", user);
        console.log("Resolver owner:", resolverOwner);
        
        // Deploy test tokens
        usdcSrc = new MockUSDC();
        usdcDst = new MockUSDC();
        
        // Deploy core contracts
        lop = new LimitOrderProtocol();
        factory = new EscrowFactory(
            address(lop),           // limitOrderProtocol
            IERC20(address(0)),     // feeToken (none for test)
            IERC20(address(0)),     // accessToken (none for test)  
            resolverOwner,          // owner (same as resolver owner)
            1 hours,                // rescueDelaySrc
            1 hours                 // rescueDelayDst
        );
        resolver = new Resolver(factory, lop, resolverOwner);
        
        // Setup tokens and approvals
        usdcSrc.mint(user, SWAP_AMOUNT * 10);
        usdcDst.mint(resolverOwner, SWAP_AMOUNT * 10);
        
        vm.deal(user, 10 ether);
        vm.deal(resolverOwner, 10 ether);
        
        // User approves LOP to spend source tokens
        vm.prank(user);
        usdcSrc.approve(address(lop), type(uint256).max);
        
        // Resolver owner approves resolver to spend destination tokens
        vm.prank(resolverOwner);
        usdcDst.approve(address(resolver), type(uint256).max);
        
        console.log("Setup completed");
    }
    
    function createTestOrder() internal view returns (IOrderMixin.Order memory) {
        return IOrderMixin.Order({
            salt: block.timestamp,
            maker: user,
            receiver: user,
            makerAsset: address(usdcSrc),
            takerAsset: address(usdcDst),
            makingAmount: SWAP_AMOUNT,
            takingAmount: SWAP_AMOUNT,
            makerTraits: 0
        });
    }
    
    function createTestOrderWithSalt(uint256 salt) internal view returns (IOrderMixin.Order memory) {
        return IOrderMixin.Order({
            salt: salt,
            maker: user,
            receiver: user,
            makerAsset: address(usdcSrc),
            takerAsset: address(usdcDst),
            makingAmount: SWAP_AMOUNT,
            takingAmount: SWAP_AMOUNT,
            makerTraits: 0
        });
    }
    
    function signOrder(IOrderMixin.Order memory order, uint256 privateKey) internal view returns (bytes32 r, bytes32 vs) {
        bytes32 orderHash = lop.hashOrder(order);
        (uint8 v, bytes32 _r, bytes32 s) = vm.sign(privateKey, orderHash);
        vs = bytes32(uint256(v - 27) << 255) | s;
        r = _r;
    }

    /**
     * @notice ✅ Flow 1: EVM-to-EVM Direct Swap
     * User → Signs Order → Resolver → fillOrderArgs() → Token Transfer
     */
    function testSimpleEVMSwap() public {
        console.log("Testing Flow 1: EVM-to-EVM Direct Swap");
        
        // User signs order
        IOrderMixin.Order memory order = createTestOrder();
        (bytes32 r, bytes32 vs) = signOrder(order, userPrivateKey);
        
        // Check initial balances
        uint256 userSrcBefore = usdcSrc.balanceOf(user);
        uint256 userDstBefore = usdcDst.balanceOf(user);
        uint256 resolverOwnerSrcBefore = usdcSrc.balanceOf(resolverOwner);
        uint256 resolverOwnerDstBefore = usdcDst.balanceOf(resolverOwner);
        
        console.log("User USDC source balance before:", userSrcBefore);
        console.log("User USDC dest balance before:", userDstBefore);
        console.log("Resolver owner USDC source balance before:", resolverOwnerSrcBefore);
        console.log("Resolver owner USDC dest balance before:", resolverOwnerDstBefore);
        
        // Resolver processes simple swap using fillOrderArgs()
        // Note: resolverOwner acts as the taker and pays destination tokens
        vm.prank(resolverOwner);
        resolver.processSimpleSwap(order, r, vs);
        
        // Verify tokens transferred
        // User should lose source tokens and gain destination tokens
        assertEq(usdcSrc.balanceOf(user), userSrcBefore - SWAP_AMOUNT, "User should have sent source tokens");
        assertEq(usdcDst.balanceOf(user), userDstBefore + SWAP_AMOUNT, "User should have received destination tokens");
        
        // Resolver owner should lose destination tokens and gain source tokens  
        assertEq(usdcDst.balanceOf(resolverOwner), resolverOwnerDstBefore - SWAP_AMOUNT, "Resolver owner should have sent destination tokens");
        assertEq(usdcSrc.balanceOf(resolverOwner), resolverOwnerSrcBefore + SWAP_AMOUNT, "Resolver owner should have received source tokens");
        
        console.log("Flow 1 completed: EVM-to-EVM Direct Swap successful");
    }

    /**
     * @notice ✅ Flow 2: EVM-to-SUI/APTOS Cross-Chain
     * User → Signs Order + Secret → Resolver → fillOrderWithPostInteraction() → EscrowFactory.postInteraction() → CrossVMOrder Created
     */
    function testCrossChainSwap() public {
        console.log("Testing Flow 2: EVM-to-SUI/APTOS Cross-Chain");
        
        // Ensure fresh tokens for this test
        usdcSrc.mint(user, SWAP_AMOUNT * 3);
        usdcDst.mint(resolverOwner, SWAP_AMOUNT * 3);
        
        // Refresh approvals
        vm.prank(user);
        usdcSrc.approve(address(lop), type(uint256).max);
        
        vm.prank(resolverOwner);
        usdcDst.approve(address(resolver), type(uint256).max);
        
        // User signs order + secret (using unique salt)
        IOrderMixin.Order memory order = createTestOrderWithSalt(block.timestamp + 1000);
        (bytes32 r, bytes32 vs) = signOrder(order, userPrivateKey);
        
        // Setup secret
        bytes32 secret = keccak256("user_secret");
        bytes32 secretHash = keccak256(abi.encodePacked(secret));
        
        // Resolver owner submits secret 
        console.log("Testing secret submission...");
        vm.startPrank(resolverOwner); 
        resolver.submitOrderAndSecret(lop.hashOrder(order), secretHash, secret);
        console.log("Secret submission successful");
        
        // Now try the full cross-chain swap 
        console.log("Testing full cross-chain swap...");
        uint8 dstVM = 1; // SUI
        uint256 dstChainId = 12345;
        string memory dstAddress = "0x5678...sui_address"; 
        resolver.processSwap(order, r, vs, dstVM, dstChainId, dstAddress);
        vm.stopPrank();

        console.log("Flow 2 completed: EVM-to-SUI Cross-Chain processed successfully!");
    }

    /**
     * @notice 🔄 Flow 3: Multi-VM Resolver Registration
     * Resolver → Registers on multiple VMs → Processes cross-chain orders
     */
    function testMultiVMResolverRegistration() public {
        console.log("Testing Flow 3: Multi-VM Resolver Registration");
        
        // Ensure fresh tokens for this test  
        // Reset balances and mint fresh tokens
        vm.deal(user, 10 ether);
        vm.deal(resolverOwner, 10 ether);
        
        // Mint fresh tokens to both parties
        usdcSrc.mint(user, SWAP_AMOUNT * 3);           // Extra for user (maker)
        usdcDst.mint(resolverOwner, SWAP_AMOUNT * 3);   // Extra for resolver owner (taker)
        
        // Refresh approvals
        vm.startPrank(user);
        usdcSrc.approve(address(lop), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(resolverOwner);
        usdcDst.approve(address(resolver), type(uint256).max);
        vm.stopPrank();
        
        console.log("Fresh tokens minted and approved");
        
        // Resolver registers on multiple VMs
        uint8[] memory vmTypes = new uint8[](3);
        vmTypes[0] = 0; // EVM
        vmTypes[1] = 1; // SUI
        vmTypes[2] = 2; // APTOS
        
        string[] memory addresses = new string[](3);
        addresses[0] = "0x1234...evm_address";
        addresses[1] = "0x5678...sui_address";
        addresses[2] = "0x9abc...aptos_address";
        
        vm.expectEmit(true, true, true, true);
        emit ResolverRegistered(vmTypes, addresses);
        
        vm.startPrank(resolverOwner);
        resolver.registerResolver(vmTypes, addresses);
        
        // Resolver can now process cross-chain orders
        IOrderMixin.Order memory order = createTestOrderWithSalt(block.timestamp + 2000);
        (bytes32 r, bytes32 vs) = signOrder(order, userPrivateKey);
        
        // vm.prank(resolverOwner);
        resolver.processSwap(order, r, vs, 2, 67890, "0x9abc...aptos_address"); // APTOS
        vm.stopPrank();
        
        console.log("Flow 3 completed: Multi-VM resolver can process cross-chain orders");
    }
 
}