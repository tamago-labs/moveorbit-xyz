// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "./interfaces/IOrderMixin.sol";

/**
 * @title LimitOrderProtocol
 * @notice Minimal implementation of Limit Order Protocol for cross-chain swaps
 * @dev Supports only ERC20 tokens, no ETH/WETH, no permits, no complex features 
 */
contract LimitOrderProtocol is IOrderMixin, EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Simple order tracking - order hash => filled amount
    mapping(bytes32 => uint256) public filledAmounts;
    
    // EIP712 type hash for Order struct
    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(uint256 salt,address maker,address receiver,address makerAsset,address takerAsset,uint256 makingAmount,uint256 takingAmount,uint256 makerTraits)"
    );

    constructor() EIP712("LimitOrderProtocol", "1") {}

    /**
     * @notice Returns the domain separator (EIP-712)
     */
    function DOMAIN_SEPARATOR() external view returns(bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @inheritdoc IOrderMixin
     */
    function hashOrder(Order calldata order) external view returns(bytes32 orderHash) {
        return _hashTypedDataV4(keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.salt,
            order.maker,
            order.receiver,
            order.makerAsset,
            order.takerAsset,
            order.makingAmount,
            order.takingAmount,
            order.makerTraits
        )));
    }

    /**
     * @inheritdoc IOrderMixin
     */
    function fillOrderArgs(
        Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        uint256 takerTraits,
        bytes calldata args
    ) external payable returns(uint256 makingAmount, uint256 takingAmount, bytes32 orderHash) {
        // Calculate order hash
        orderHash = _hashTypedDataV4(keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.salt,
            order.maker,
            order.receiver,
            order.makerAsset,
            order.takerAsset,
            order.makingAmount,
            order.takingAmount,
            order.makerTraits
        )));

        // Check if order is already filled
        if (filledAmounts[orderHash] >= order.makingAmount) {
            revert InvalidatedOrder();
        }

        // Verify signature
        address signer = orderHash.recover(r, vs);
        if (signer != order.maker) {
            revert BadSignature();
        }

        // For simplicity, we only support full fills in this minimal version
        makingAmount = order.makingAmount;
        takingAmount = order.takingAmount;

        // Mark order as filled
        filledAmounts[orderHash] = makingAmount;

        // Parse target from args (first 20 bytes if present)
        address target = msg.sender; // Default to sender
        if (args.length >= 20) {
            target = address(bytes20(args[:20]));
        }

        // Transfer maker asset to taker/target
        if (!_safeTransferFrom(order.makerAsset, order.maker, target, makingAmount)) {
            revert TransferFromMakerToTakerFailed();
        }

        // Transfer taker asset to maker's receiver
        address receiver = order.receiver != address(0) ? order.receiver : order.maker;
        if (!_safeTransferFrom(order.takerAsset, msg.sender, receiver, takingAmount)) {
            revert TransferFromTakerToMakerFailed();
        }

        emit OrderFilled(orderHash, 0); // 0 remaining since we only do full fills
    }

    /**
     * @notice Safe transfer from with error handling
     * @param token Token address
     * @param from From address  
     * @param to To address
     * @param amount Amount to transfer
     * @return success Whether transfer succeeded
     */
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private returns(bool success) {
        try IERC20(token).transferFrom(from, to, amount) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Check if order is filled
     * @param orderHash Hash of the order
     * @return filled Amount filled for this order
     */
    function getFilledAmount(bytes32 orderHash) external view returns(uint256 filled) {
        return filledAmounts[orderHash];
    }

    /**
     * @notice Check remaining amount for order
     * @param order The order to check
     * @return remaining Remaining amount that can be filled
     */
    function remainingAmount(Order calldata order) external view returns(uint256 remaining) {
        bytes32 orderHash = _hashTypedDataV4(keccak256(abi.encode(
            ORDER_TYPEHASH,
            order.salt,
            order.maker,
            order.receiver,
            order.makerAsset,
            order.takerAsset,
            order.makingAmount,
            order.takingAmount,
            order.makerTraits
        )));
        
        uint256 filled = filledAmounts[orderHash];
        return filled >= order.makingAmount ? 0 : order.makingAmount - filled;
    }
}
