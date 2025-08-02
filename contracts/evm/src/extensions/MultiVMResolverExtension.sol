
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IOrderMixin } from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import { Address, AddressLib } from "solidity-utils/contracts/libraries/AddressLib.sol";

import { BaseExtension } from "./BaseExtension.sol";

/**
 * @title Multi-VM Resolver Extension
 * @notice Simplified extension to enable resolvers to work across EVM, SUI, and Aptos chains
 * @dev Streamlined for hackathon
 */
abstract contract MultiVMResolverExtension is BaseExtension { 

    using AddressLib for Address; 

    // Supported VM types
    enum VMType { EVM, SUI, APTOS }

    // Simplified resolver data
    struct ResolverProfile {
        VMType[] supportedVMs;
        mapping(VMType => string) vmAddress; // VM-specific addresses as strings
        bool isActive;
        uint256 registrationTime;
    }

    // Cross-VM order tracking
    struct CrossVMOrder {
        bytes32 orderHash;
        VMType srcVM;
        VMType dstVM;
        address resolver;
        uint256 srcChainId;
        uint256 dstChainId;
        string dstAddress; // Destination VM address as string
        bool isProcessed;
    }

    // Events for demo
    event ResolverRegistered(
        address indexed resolver,
        VMType[] supportedVMs,
        string[] vmAddresses
    );

    event CrossVMOrderCreated(
        bytes32 indexed orderHash,
        address indexed resolver,
        VMType srcVM,
        VMType dstVM,
        uint256 srcChainId,
        uint256 dstChainId,
        string dstAddress
    );

    event CrossVMOrderProcessed(
        bytes32 indexed orderHash,
        VMType vmType,
        string vmAddress,
        uint256 amount
    );

    // State variables
    mapping(address => ResolverProfile) public resolverProfiles;
    mapping(bytes32 => CrossVMOrder) public crossVMOrders;
    mapping(address => bytes32[]) public resolverOrders; // Track orders per resolver
    address[] public registeredResolvers;
    bytes32[] public allOrders; // Track all orders for iteration

    // Simple configuration
    mapping(VMType => bool) public supportedVMs;

    constructor() {
        // Enable all VM types for demo
        supportedVMs[VMType.EVM] = true;
        supportedVMs[VMType.SUI] = true;
        supportedVMs[VMType.APTOS] = true;
    }

    /**
     * @notice Get resolver's address for specific VM
     * @param resolver The resolver address
     * @param vmType The VM type
     * @return vmAddress The address on that VM
     */
    function getResolverVMAddress(address resolver, VMType vmType) external view returns (string memory) {
        return resolverProfiles[resolver].vmAddress[vmType];
    }

    // Internal helper functions

    function _parseDestinationVM(bytes calldata extraData) internal pure returns (
        VMType dstVM,
        uint256 dstChainId,
        string memory dstAddress
    ) {
        // Simple parsing for hackathon demo
        // Format: [0:1] vmType, [1:33] chainId, [33:] address
        
        dstVM = VMType(uint8(bytes1(extraData[0:1])));
        dstChainId = uint256(bytes32(extraData[1:33]));
        
        // Convert remaining bytes to string (simplified)
        bytes memory addressBytes = extraData[33:];
        dstAddress = string(addressBytes);
    }

    function _createCrossVMOrder(
        bytes32 orderHash,
        address resolver,
        VMType dstVM,
        uint256 dstChainId,
        string memory dstAddress,
        uint256 /* amount */ // Unused in current implementation
    ) internal {
        // Validate resolver supports destination VM
        require(resolverProfiles[resolver].isActive, "Resolver not registered");
        require(_resolverSupportsVM(resolver, dstVM), "Resolver doesn't support destination VM");

        CrossVMOrder memory crossVMOrder = CrossVMOrder({
            orderHash: orderHash,
            srcVM: VMType.EVM, // Current chain is EVM
            dstVM: dstVM,
            resolver: resolver,
            srcChainId: block.chainid,
            dstChainId: dstChainId,
            dstAddress: dstAddress,
            isProcessed: false
        });
        
        crossVMOrders[orderHash] = crossVMOrder;
        
        // Track this order for the resolver
        resolverOrders[resolver].push(orderHash);
        allOrders.push(orderHash);
        
        emit CrossVMOrderCreated(
            orderHash,
            resolver,
            VMType.EVM,
            dstVM,
            block.chainid,
            dstChainId,
            dstAddress
        );
    }

    function _resolverSupportsVM(address resolver, VMType vmType) internal view returns (bool) {
        ResolverProfile storage profile = resolverProfiles[resolver];
        
        for (uint256 i = 0; i < profile.supportedVMs.length; i++) {
            if (profile.supportedVMs[i] == vmType) return true;
        }
        return false;
    }

    // View functions for dashboard

    function getTotalResolvers() external view returns (uint256) {
        return registeredResolvers.length;
    }

    function getTotalOrders() external view returns (uint256) {
        return allOrders.length;
    }

    function getResolverInfo(address resolver) external view returns (
        VMType[] memory resolverSupportedVMs,
        bool isActive,
        uint256 registrationTime,
        uint256 orderCount
    ) {
        ResolverProfile storage profile = resolverProfiles[resolver];
        return (
            profile.supportedVMs, 
            profile.isActive, 
            profile.registrationTime,
            resolverOrders[resolver].length
        );
    }

    function getCrossVMOrderInfo(bytes32 orderHash) external view returns (
        VMType srcVM,
        VMType dstVM,
        address resolver,
        uint256 srcChainId,
        uint256 dstChainId,
        string memory dstAddress,
        bool isProcessed
    ) {
        CrossVMOrder storage order = crossVMOrders[orderHash];
        return (
            order.srcVM,
            order.dstVM,
            order.resolver,
            order.srcChainId,
            order.dstChainId,
            order.dstAddress,
            order.isProcessed
        );
    }

    // Helper function to convert VM type to string for frontend
    function vmTypeToString(VMType vmType) external pure returns (string memory) {
        if (vmType == VMType.EVM) return "EVM";
        if (vmType == VMType.SUI) return "SUI";
        if (vmType == VMType.APTOS) return "APTOS";
        return "UNKNOWN";
    }

    /**
     * @notice Register as a multi-VM resolver
     * @param vms Array of VM types the resolver supports
     * @param addresses Array of addresses for each VM type
     */
    function registerResolver(
        VMType[] calldata vms,
        string[] calldata addresses
    ) external {
        require(vms.length == addresses.length, "Array length mismatch");
        require(vms.length > 0, "Must support at least one VM");
        require(!resolverProfiles[msg.sender].isActive, "Already registered");

        ResolverProfile storage profile = resolverProfiles[msg.sender];
        
        for (uint256 i = 0; i < vms.length; i++) {
            require(supportedVMs[vms[i]], "VM type not supported");
            profile.supportedVMs.push(vms[i]);
            profile.vmAddress[vms[i]] = addresses[i];
        }

        profile.isActive = true;
        profile.registrationTime = block.timestamp;
        registeredResolvers.push(msg.sender);

        emit ResolverRegistered(msg.sender, vms, addresses);
    }

    /**
     * @notice Enhanced post-interaction for cross-VM orders
     */
    function _postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal virtual override {
        // Parse destination VM info from extraData (simplified)
        if (extraData.length >= 66) { // Minimum size for VM data
            (VMType dstVM, uint256 dstChainId, string memory dstAddress) = _parseDestinationVM(extraData);
            
            // Only process if it's a cross-VM order
            if (dstVM != VMType.EVM || dstChainId != block.chainid) {
                _createCrossVMOrder(orderHash, taker, dstVM, dstChainId, dstAddress, makingAmount);
            }
        }
        
        super._postInteraction(order, extension, orderHash, taker, makingAmount, takingAmount, remainingMakingAmount, extraData);
    }

    /**
     * @notice Mark order as processed on destination VM
     * @param orderHash The order hash
     * @param vmType The VM where processing occurred
     * @param vmTxId Transaction ID on the destination VM
     */
    function markOrderProcessed(
        bytes32 orderHash,
        VMType vmType,
        string calldata vmTxId
    ) external {
        CrossVMOrder storage order = crossVMOrders[orderHash];
        require(order.orderHash != bytes32(0), "Order not found");
        require(order.resolver == msg.sender, "Not order resolver");
        require(!order.isProcessed, "Already processed");

        order.isProcessed = true;

        emit CrossVMOrderProcessed(
            orderHash,
            vmType,
            vmTxId,
            block.timestamp
        );
    }

    /**
     * @notice Get orders for a specific resolver (for demo dashboard)
     * @param resolver The resolver address
     * @return orderHashes Array of order hashes for this resolver
     */
    function getResolverOrders(address resolver) external view returns (bytes32[] memory) {
        return resolverOrders[resolver];
    }

    /**
     * @notice Get all cross-VM orders (for demo dashboard)
     * @return orderHashes Array of all order hashes
     */
    function getAllOrders() external view returns (bytes32[] memory) {
        return allOrders;
    }

    /**
     * @notice Get paginated orders for a resolver
     * @param resolver The resolver address
     * @param offset Starting index
     * @param limit Maximum number of orders to return
     * @return orderHashes Array of order hashes
     * @return total Total number of orders for this resolver
     */
    function getResolverOrdersPaginated(
        address resolver, 
        uint256 offset, 
        uint256 limit
    ) external view returns (bytes32[] memory orderHashes, uint256 total) {
        bytes32[] storage orders = resolverOrders[resolver];
        total = orders.length;
        
        if (offset >= total) {
            return (new bytes32[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        uint256 length = end - offset;
        orderHashes = new bytes32[](length);
        
        for (uint256 i = 0; i < length; i++) {
            orderHashes[i] = orders[offset + i];
        }
        
        return (orderHashes, total);
    }

    /**
     * @notice Get order count for a resolver
     * @param resolver The resolver address
     * @return count Number of orders for this resolver
     */
    function getResolverOrderCount(address resolver) external view returns (uint256) {
        return resolverOrders[resolver].length;
    }

    /**
     * @notice Check if resolver supports specific VM type
     * @param resolver The resolver address
     * @param vmType The VM type to check
     * @return supported True if resolver supports the VM type
     */
    function supportsVM(address resolver, VMType vmType) external view returns (bool) {
        ResolverProfile storage profile = resolverProfiles[resolver];
        if (!profile.isActive) return false;

        for (uint256 i = 0; i < profile.supportedVMs.length; i++) {
            if (profile.supportedVMs[i] == vmType) return true;
        }
        return false;
    }
}