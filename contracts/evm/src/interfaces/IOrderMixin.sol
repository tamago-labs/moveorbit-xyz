// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IOrderMixin  
 * @notice Simplified interface that only includes functionality needed for cross-chain swaps
 */
interface IOrderMixin {
    
    struct Order {
        uint256 salt;
        address maker;
        address receiver; 
        address makerAsset;
        address takerAsset;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 makerTraits; // Simplified to uint256
    }

    // Essential events
    event OrderFilled(bytes32 indexed orderHash, uint256 remainingAmount);
    
    // Essential errors
    error InvalidatedOrder();
    error BadSignature();
    error TransferFromMakerToTakerFailed();
    error TransferFromTakerToMakerFailed();

    /**
     * @notice Fills order for cross-chain swap - simplified version
     * @param order Order to fill
     * @param r R component of signature
     * @param vs VS component of signature  
     * @param amount Amount to fill
     * @param takerTraits Taker preferences (simplified)
     * @param args Additional arguments (target address, etc)
     * @return makingAmount Actual amount from maker
     * @return takingAmount Actual amount from taker
     * @return orderHash Hash of the order
     */
    function fillOrderArgs(
        Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        uint256 takerTraits, // Simplified to uint256
        bytes calldata args
    ) external payable returns(uint256 makingAmount, uint256 takingAmount, bytes32 orderHash);

    /**
     * @notice Returns order hash for EIP712 signature
     */
    function hashOrder(Order calldata order) external view returns(bytes32 orderHash);
}
