// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "./interfaces/IOrderMixin.sol";

// Import post-interaction interface
interface IPostInteraction {
    function postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external;
}

/**
 * @title LimitOrderProtocol
 * @notice Simplified Limit Order Protocol for cross-chain swaps between EVM <> Move
 * @dev Supports ERC20 tokens with post-interaction hooks for escrow creation
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

    // Constants for taker traits parsing
    uint256 private constant _ARGS_HAS_TARGET = 1 << 251;

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

        // Parse target from args or taker traits
        address target = _parseTarget(takerTraits, args);

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
     * @notice Fill order with post-interaction hook for cross-chain swaps
     * @param order Order to fill
     * @param r R component of signature
     * @param vs VS component of signature  
     * @param amount Amount to fill
     * @param takerTraits Taker preferences
     * @param args Target address and other args
     * @param extension Extension data for post-interaction
     * @param extraData Extra data for post-interaction (contains VM info for cross-chain)
     * @return makingAmount Actual amount from maker
     * @return takingAmount Actual amount from taker  
     * @return orderHash Hash of the order
     */
    function fillOrderWithPostInteraction(
        Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        uint256 takerTraits,
        bytes calldata args,
        bytes calldata extension,
        bytes calldata extraData
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
        uint256 remainingMakingAmount = 0; // Always 0 for full fills

        // Mark order as filled
        filledAmounts[orderHash] = makingAmount;

        // Parse target from args or taker traits
        address target = _parseTarget(takerTraits, args);

        // Transfer maker asset to taker/target
        if (!_safeTransferFrom(order.makerAsset, order.maker, target, makingAmount)) {
            revert TransferFromMakerToTakerFailed();
        }

        // Transfer taker asset to maker's receiver
        address receiver = order.receiver != address(0) ? order.receiver : order.maker;
        if (!_safeTransferFrom(order.takerAsset, msg.sender, receiver, takingAmount)) {
            revert TransferFromTakerToMakerFailed();
        }

        // Trigger post-interaction if extraData is provided (indicates cross-chain swap)
        if (extraData.length > 0 && target != address(0)) {
            try IPostInteraction(target).postInteraction(
                order, 
                extension, 
                orderHash, 
                msg.sender, 
                makingAmount, 
                takingAmount, 
                remainingMakingAmount, 
                extraData
            ) {
                // Post-interaction succeeded
            } catch {
                // Post-interaction failed - order still succeeds but escrow won't be created
                // This allows fallback to simple EVM-to-EVM swaps
            }
        }

        emit OrderFilled(orderHash, remainingMakingAmount);
    }

    /**
     * @notice Parse target address from taker traits and args
     * @param takerTraits Taker traits containing flags
     * @param args Arguments containing target address
     * @return target The target address for transfers
     */
    function _parseTarget(uint256 takerTraits, bytes calldata args) internal view returns(address target) {
        if (takerTraits & _ARGS_HAS_TARGET != 0 && args.length >= 20) {
            // Target is specified in first 20 bytes of args
            target = address(bytes20(args[:20]));
        } else {
            // Default to sender
            target = msg.sender;
        }
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

    /**
     * @notice Helper function to create extraData for cross-chain swaps
     * @param dstVM Destination VM type (0=EVM, 1=SUI, 2=APTOS)
     * @param dstChainId Destination chain ID
     * @param dstAddress Destination address as string
     * @return extraData Encoded extra data for post-interaction
     */
    function encodeExtraDataForVM(
        uint8 dstVM,
        uint256 dstChainId,
        string calldata dstAddress
    ) external pure returns(bytes memory extraData) {
        return abi.encodePacked(dstVM, dstChainId, bytes(dstAddress));
    }
}
