// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/LimitOrderProtocol.sol";
import "../src/MockUSDC.sol";

contract LimitOrderProtocolTest is Test {
    LimitOrderProtocol public lop;
    MockUSDC public tokenA; // Maker asset (USDC)
    MockUSDC public tokenB; // Taker asset (another token)
    
    address public maker = address(0x1);
    address public taker = address(0x2);
    address public receiver = address(0x3);
    
    uint256 public makerPrivateKey = 0xA11CE;
    uint256 public takerPrivateKey = 0xB0B;
    
    // Test order parameters
    uint256 public constant MAKING_AMOUNT = 1000 * 1e6; // 1000 USDC
    uint256 public constant TAKING_AMOUNT = 2000 * 1e6; // 2000 TokenB
    uint256 public constant SALT = 12345;
    
    function setUp() public {
        // Deploy contracts
        lop = new LimitOrderProtocol();
        tokenA = new MockUSDC(); // USDC for maker
        tokenB = new MockUSDC(); // Another token for taker
        
        // Setup accounts with correct private keys
        maker = vm.addr(makerPrivateKey);
        taker = vm.addr(takerPrivateKey);
        
        // Mint tokens
        tokenA.mint(maker, 10000 * 1e6); // Mint 10,000 USDC to maker
        tokenB.mint(taker, 10000 * 1e6); // Mint 10,000 TokenB to taker
        
        // Approve LOP to spend tokens
        vm.prank(maker);
        tokenA.approve(address(lop), type(uint256).max);
        
        vm.prank(taker);
        tokenB.approve(address(lop), type(uint256).max);
        
        // Label addresses for better traces
        vm.label(maker, "Maker");
        vm.label(taker, "Taker");
        vm.label(receiver, "Receiver");
        vm.label(address(lop), "LimitOrderProtocol");
        vm.label(address(tokenA), "TokenA");
        vm.label(address(tokenB), "TokenB");
    }
    
    function test_DeploymentAndBasicState() public {
        // Test basic deployment state
        assertEq(lop.DOMAIN_SEPARATOR(), lop.DOMAIN_SEPARATOR());
        assertTrue(lop.DOMAIN_SEPARATOR() != bytes32(0));
    }
    
    function test_HashOrderConsistency() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        
        bytes32 hash1 = lop.hashOrder(order);
        bytes32 hash2 = lop.hashOrder(order);
        
        assertEq(hash1, hash2, "Hash should be consistent");
        assertTrue(hash1 != bytes32(0), "Hash should not be zero");
        
        // Different salt should produce different hash
        order.salt = SALT + 1;
        bytes32 hash3 = lop.hashOrder(order);
        assertTrue(hash1 != hash3, "Different salt should produce different hash");
    }
    
    function test_FillOrderBasic() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        // Record initial balances
        uint256 makerTokenABefore = tokenA.balanceOf(maker);
        uint256 takerTokenBBefore = tokenB.balanceOf(taker);
        uint256 takerTokenABefore = tokenA.balanceOf(taker);
        uint256 makerTokenBBefore = tokenB.balanceOf(maker);
        
        // Fill order
        vm.prank(taker);
        (uint256 makingAmount, uint256 takingAmount, bytes32 orderHash) = lop.fillOrderArgs(
            order,
            r,
            vs,
            MAKING_AMOUNT,
            0, // takerTraits
            "" // no args
        );
        
        // Verify return values
        assertEq(makingAmount, MAKING_AMOUNT, "Making amount should match");
        assertEq(takingAmount, TAKING_AMOUNT, "Taking amount should match");
        assertTrue(orderHash != bytes32(0), "Order hash should not be zero");
        
        // Verify token transfers
        assertEq(tokenA.balanceOf(maker), makerTokenABefore - MAKING_AMOUNT, "Maker should lose tokenA");
        assertEq(tokenA.balanceOf(taker), takerTokenABefore + MAKING_AMOUNT, "Taker should gain tokenA");
        assertEq(tokenB.balanceOf(taker), takerTokenBBefore - TAKING_AMOUNT, "Taker should lose tokenB");
        assertEq(tokenB.balanceOf(maker), makerTokenBBefore + TAKING_AMOUNT, "Maker should gain tokenB");
        
        // Verify order is marked as filled
        assertEq(lop.getFilledAmount(orderHash), MAKING_AMOUNT, "Order should be fully filled");
        assertEq(lop.remainingAmount(order), 0, "No remaining amount");
    }
    
    function test_FillOrderWithCustomReceiver() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        order.receiver = receiver; // Set custom receiver
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        uint256 receiverTokenBBefore = tokenB.balanceOf(receiver);
        
        vm.prank(taker);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
        
        // Taker asset should go to custom receiver, not maker
        assertEq(tokenB.balanceOf(receiver), receiverTokenBBefore + TAKING_AMOUNT, "Receiver should get taker asset");
        assertEq(tokenB.balanceOf(maker), 0, "Maker should not get taker asset");
    }
    
    function test_FillOrderWithTarget() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        address target = address(0x999);
        bytes memory args = abi.encodePacked(target); // Pack target address
        
        uint256 targetTokenABefore = tokenA.balanceOf(target);
        uint256 takerTokenABefore = tokenA.balanceOf(taker);
        
        // Use the _ARGS_HAS_TARGET flag (1 << 251) to enable target parsing
        uint256 takerTraits = 1 << 251;
        
        vm.prank(taker);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, takerTraits, args);
        
        // Maker asset should go to target when _ARGS_HAS_TARGET flag is set
        assertEq(tokenA.balanceOf(target), targetTokenABefore + MAKING_AMOUNT, "Target should get maker asset");
        assertEq(tokenA.balanceOf(taker), takerTokenABefore, "Taker should not get maker asset when target is specified");
    }
    
    function test_RevertAlreadyFilled() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        // Fill order first time
        vm.prank(taker);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
        
        // Try to fill again - should revert
        vm.prank(taker);
        vm.expectRevert(IOrderMixin.InvalidatedOrder.selector);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
    }
    
    function test_RevertBadSignature() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        (bytes32 r, bytes32 vs) = _signOrder(order, takerPrivateKey); // Wrong signer
        
        vm.prank(taker);
        vm.expectRevert(IOrderMixin.BadSignature.selector);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
    }
    
    function test_RevertInsufficientAllowance() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        // Remove maker's allowance
        vm.prank(maker);
        tokenA.approve(address(lop), 0);
        
        vm.prank(taker);
        vm.expectRevert(IOrderMixin.TransferFromMakerToTakerFailed.selector);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
    }
    
    function test_RevertInsufficientBalance() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        order.makingAmount = 20000 * 1e6; // More than maker has
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        vm.prank(taker);
        vm.expectRevert(IOrderMixin.TransferFromMakerToTakerFailed.selector);
        lop.fillOrderArgs(order, r, vs, order.makingAmount, 0, "");
    }
    
    function test_EventEmission() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        bytes32 expectedOrderHash = lop.hashOrder(order);
        
        // Expect OrderFilled event
        vm.expectEmit(true, false, false, true);
        emit IOrderMixin.OrderFilled(expectedOrderHash, 0);
        
        vm.prank(taker);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
    }
    
    function test_MultipleOrdersWithDifferentSalts() public {
        // Create and fill first order
        IOrderMixin.Order memory order1 = _createBasicOrder();
        (bytes32 r1, bytes32 vs1) = _signOrder(order1, makerPrivateKey);
        
        vm.prank(taker);
        lop.fillOrderArgs(order1, r1, vs1, MAKING_AMOUNT, 0, "");
        
        // Create second order with different salt
        IOrderMixin.Order memory order2 = _createBasicOrder();
        order2.salt = SALT + 1;
        (bytes32 r2, bytes32 vs2) = _signOrder(order2, makerPrivateKey);
        
        // Should be able to fill second order
        vm.prank(taker);
        lop.fillOrderArgs(order2, r2, vs2, MAKING_AMOUNT, 0, "");
        
        // Both orders should be filled
        assertEq(lop.getFilledAmount(lop.hashOrder(order1)), MAKING_AMOUNT);
        assertEq(lop.getFilledAmount(lop.hashOrder(order2)), MAKING_AMOUNT);
    }
    
    function test_RemainingAmountView() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        
        // Before filling
        assertEq(lop.remainingAmount(order), MAKING_AMOUNT, "Should have full amount remaining");
        
        // After filling
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        vm.prank(taker);
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
        
        assertEq(lop.remainingAmount(order), 0, "Should have no amount remaining");
    }
    
    function test_DomainSeparator() public {
        bytes32 domainSeparator = lop.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0), "Domain separator should not be zero");
        
        // Domain separator should be consistent
        assertEq(domainSeparator, lop.DOMAIN_SEPARATOR(), "Domain separator should be consistent");
    }
    
    // Helper function to create a basic order
    function _createBasicOrder() internal view returns (IOrderMixin.Order memory) {
        return IOrderMixin.Order({
            salt: SALT,
            maker: maker,
            receiver: address(0), // Use maker as receiver by default
            makerAsset: address(tokenA),
            takerAsset: address(tokenB),
            makingAmount: MAKING_AMOUNT,
            takingAmount: TAKING_AMOUNT,
            makerTraits: 0 // No special traits
        });
    }
    
    // Helper function to sign an order
    function _signOrder(IOrderMixin.Order memory order, uint256 privateKey) 
        internal 
        view 
        returns (bytes32 r, bytes32 vs) 
    {
        bytes32 orderHash = lop.hashOrder(order);
        (uint8 v, bytes32 _r, bytes32 s) = vm.sign(privateKey, orderHash);
        
        // Convert to compact signature format (r, vs)
        r = _r;
        vs = bytes32(uint256(v - 27) << 255 | uint256(s));
    }
    
    // Fuzz test with different amounts
    function testFuzz_FillOrderAmounts(uint128 makingAmount, uint128 takingAmount) public {
        // Bound amounts to reasonable values
        makingAmount = uint128(bound(makingAmount, 1, 5000 * 1e6));
        takingAmount = uint128(bound(takingAmount, 1, 5000 * 1e6));
        
        IOrderMixin.Order memory order = _createBasicOrder();
        order.makingAmount = makingAmount;
        order.takingAmount = takingAmount;
        order.salt = SALT + 999; // Different salt for fuzz test
        
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        uint256 makerTokenABefore = tokenA.balanceOf(maker);
        uint256 takerTokenBBefore = tokenB.balanceOf(taker);
        
        vm.prank(taker);
        (uint256 returnedMakingAmount, uint256 returnedTakingAmount,) = 
            lop.fillOrderArgs(order, r, vs, makingAmount, 0, "");
        
        assertEq(returnedMakingAmount, makingAmount, "Returned making amount should match");
        assertEq(returnedTakingAmount, takingAmount, "Returned taking amount should match");
        assertEq(tokenA.balanceOf(maker), makerTokenABefore - makingAmount, "Maker balance should decrease");
        assertEq(tokenB.balanceOf(taker), takerTokenBBefore - takingAmount, "Taker balance should decrease");
    }
    
    // Test gas consumption
    function test_GasConsumption() public {
        IOrderMixin.Order memory order = _createBasicOrder();
        (bytes32 r, bytes32 vs) = _signOrder(order, makerPrivateKey);
        
        vm.prank(taker);
        uint256 gasBefore = gasleft();
        lop.fillOrderArgs(order, r, vs, MAKING_AMOUNT, 0, "");
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for fillOrderArgs:", gasUsed);
        
        // Expect reasonable gas usage (should be less than 150k gas)
        assertTrue(gasUsed < 150000, "Gas usage should be reasonable");
    }
}
