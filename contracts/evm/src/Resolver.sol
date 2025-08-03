// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// import {IOrderMixin} from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import {IOrderMixin} from "./interfaces/IOrderMixin.sol";

import {IResolverExample} from "cross-chain-swap/interfaces/IResolverExample.sol";
import {RevertReasonForwarder} from "solidity-utils/contracts/libraries/RevertReasonForwarder.sol";
import {IEscrowFactory} from "cross-chain-swap/interfaces/IEscrowFactory.sol";
import {IBaseEscrow} from "cross-chain-swap/interfaces/IBaseEscrow.sol";
import {TimelocksLib, Timelocks} from "cross-chain-swap/libraries/TimelocksLib.sol";
import {IEscrow} from "cross-chain-swap/interfaces/IEscrow.sol";
import {ImmutablesLib} from "cross-chain-swap/libraries/ImmutablesLib.sol";

// Import MultiVM types
import {MultiVMResolverExtension} from "./extensions/MultiVMResolverExtension.sol";

// Interface for our enhanced LimitOrderProtocol
interface ILimitOrderProtocol {
    function fillOrderArgs(
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        uint256 takerTraits,
        bytes calldata args
    ) external payable returns(uint256 makingAmount, uint256 takingAmount, bytes32 orderHash);

    function fillOrderWithPostInteraction(
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        uint256 takerTraits,
        bytes calldata args,
        bytes calldata extension,
        bytes calldata extraData
    ) external payable returns(uint256 makingAmount, uint256 takingAmount, bytes32 orderHash);
}

/**
 * @title Resolver contract for cross-chain swap with multi-VM support
 * @notice Supports EVM, SUI, and APTOS cross-chain swaps with secret management
 * @dev Implements all functions referenced in the flow documentation
 */
contract Resolver is Ownable {
    using ImmutablesLib for IBaseEscrow.Immutables;
    using TimelocksLib for Timelocks;

    error InvalidLength();
    error LengthMismatch();
    error SecretNotFound();
    error InvalidVMType();

    // VM Types matching MultiVMResolverExtension
    enum VMType { EVM, SUI, APTOS }

    // Events
    event SecretSubmitted(bytes32 indexed orderHash, bytes32 indexed secretHash);
    event SimpleSwapProcessed(bytes32 indexed orderHash, address indexed maker, address indexed taker);
    event CrossChainSwapProcessed(
        bytes32 indexed orderHash, 
        VMType dstVM, 
        uint256 dstChainId, 
        string dstAddress
    );
    event ResolverRegistered(uint8[] vmTypes, string[] addresses);

    IEscrowFactory private immutable _FACTORY;
    IOrderMixin private immutable _LOP;

    // Secret management for cross-chain swaps
    mapping(bytes32 => bytes32) private secretStorage; // orderHash => secret
    mapping(bytes32 => bytes32) private secretHashStorage; // orderHash => secretHash

    // Constants for taker traits
    uint256 private constant _ARGS_HAS_TARGET = 1 << 251;

    constructor(IEscrowFactory factory, IOrderMixin lop, address initialOwner) Ownable(initialOwner) {
        _FACTORY = factory;
        _LOP = lop;
    }

    receive() external payable {} // solhint-disable-line no-empty-blocks

    /**
     * @notice Submit order and secret for cross-chain swap
     * @param orderHash Hash of the order
     * @param secretHash Hash of the secret
     * @param secret The actual secret for atomic swap
     */
    function submitOrderAndSecret(
        bytes32 orderHash, 
        bytes32 secretHash, 
        bytes32 secret
    ) external onlyOwner {
        // Verify secret hash matches
        require(keccak256(abi.encodePacked(secret)) == secretHash, "Secret hash mismatch");
        
        // Store secret and hash
        secretStorage[orderHash] = secret;
        secretHashStorage[orderHash] = secretHash;
        
        emit SecretSubmitted(orderHash, secretHash);
    }

    /**
     * @notice Process simple EVM-to-EVM swap
     * @param order The order to process
     * @param r R component of signature
     * @param vs VS component of signature
     */
    function processSimpleSwap(
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs
    ) external onlyOwner {
        // First, transfer the required taker asset from owner to this contract
        // This allows the contract to be the taker in the LOP transaction
        IERC20(order.takerAsset).transferFrom(msg.sender, address(this), order.takingAmount);
        
        // Approve LOP to spend the taker asset from this contract
        IERC20(order.takerAsset).approve(address(_LOP), order.takingAmount);
        
        // Fill order using standard fillOrderArgs (no post-interaction)
        (uint256 makingAmount, uint256 takingAmount, bytes32 orderHash) = 
            ILimitOrderProtocol(address(_LOP)).fillOrderArgs(order, r, vs, order.makingAmount, 0, "");
        
        // Transfer the received maker asset to the owner
        IERC20(order.makerAsset).transfer(msg.sender, makingAmount);
        
        emit SimpleSwapProcessed(orderHash, order.maker, msg.sender);
    }

    /**
     * @notice Process cross-chain swap 
     * @param order The order to process
     * @param r R component of signature  
     * @param vs VS component of signature
     * @param dstVM Destination VM type (1=SUI, 2=APTOS)
     * @param dstChainId Destination chain ID
     * @param dstAddress Destination address as string
     */
    function processSwap(
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint8 dstVM,
        uint256 dstChainId,
        string calldata dstAddress
    ) external onlyOwner {
        // Validate VM type
        if (dstVM == 0 || dstVM > 2) revert InvalidVMType();
        
        // First, transfer the required taker asset from owner to this contract
        // This allows the contract to be the taker in the LOP transaction
        IERC20(order.takerAsset).transferFrom(msg.sender, address(this), order.takingAmount);
        
        // Approve LOP to spend the taker asset from this contract
        IERC20(order.takerAsset).approve(address(_LOP), order.takingAmount);
        
        // Create extraData for cross-chain swap
        bytes memory extraData = abi.encodePacked(dstVM, dstChainId, bytes(dstAddress));
        
        // For cross-chain swaps, we want:
        // 1. Maker asset to come to Resolver (so we can forward to resolverOwner)
        // 2. Post-interaction to be called on Factory with cross-chain data
        // Solution: Don't use _ARGS_HAS_TARGET, let maker asset come to resolver (msg.sender)
        uint256 takerTraits = 0; // No special target, maker asset comes to resolver
        
        // Args can contain additional data for post-interaction, but target is determined by takerTraits
        bytes memory args = "";
        
        // Fill order with post-interaction to trigger escrow creation
        (uint256 makingAmount, uint256 takingAmount, bytes32 orderHash) = 
            ILimitOrderProtocol(address(_LOP)).fillOrderWithPostInteraction(
                order, 
                r, 
                vs, 
                order.makingAmount, 
                takerTraits, 
                args,
                "", // extension (empty for now)
                extraData
            );
        
        // Transfer the received maker asset to the owner
        IERC20(order.makerAsset).transfer(msg.sender, makingAmount);
        
        emit CrossChainSwapProcessed(orderHash, VMType(dstVM), dstChainId, dstAddress);
    }

    /**
     * @notice Register as multi-VM resolver
     * @param vmTypes Array of VM types (0=EVM, 1=SUI, 2=APTOS)
     * @param addresses Array of addresses for each VM
     */
    function registerResolver(
        uint8[] calldata vmTypes,
        string[] calldata addresses
    ) external onlyOwner {
        require(vmTypes.length == addresses.length, "Array length mismatch");
        require(vmTypes.length > 0, "Must support at least one VM");
        
        // Validate VM types
        for (uint256 i = 0; i < vmTypes.length; i++) {
            if (vmTypes[i] > 2) revert InvalidVMType();
        }
        
        // Emit event for registration (actual registration happens through EscrowFactory)
        emit ResolverRegistered(vmTypes, addresses);
        
        // Note: The actual registration with MultiVMResolverExtension happens
        // when the resolver calls the EscrowFactory functions. This is a 
        // simplified interface for the demo.
    }

    /**
     * @notice Get stored secret for an order
     * @param orderHash Hash of the order
     * @return secret The stored secret
     */
    function getSecret(bytes32 orderHash) external view onlyOwner returns (bytes32 secret) {
        secret = secretStorage[orderHash];
        if (secret == bytes32(0)) revert SecretNotFound();
    }

    /**
     * @notice Get stored secret hash for an order
     * @param orderHash Hash of the order
     * @return secretHash The stored secret hash
     */
    function getSecretHash(bytes32 orderHash) external view returns (bytes32 secretHash) {
        return secretHashStorage[orderHash];
    }

    /**
     * @notice Check if resolver has secret for order
     * @param orderHash Hash of the order
     * @return True if secret is stored
     */
    function hasSecret(bytes32 orderHash) external view returns (bool) {
        return secretStorage[orderHash] != bytes32(0);
    }

    /**
     * @notice Deploy source chain escrow (original function)
     */
    function deploySrc(
        IBaseEscrow.Immutables calldata immutables,
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        uint256 takerTraits,
        bytes calldata args
    ) external payable onlyOwner {

        IBaseEscrow.Immutables memory immutablesMem = immutables;
        immutablesMem.timelocks = TimelocksLib.setDeployedAt(immutables.timelocks, block.timestamp);
        address computed = _FACTORY.addressOfEscrowSrc(immutablesMem);

        (bool success,) = address(computed).call{value: immutablesMem.safetyDeposit}("");
        if (!success) revert IBaseEscrow.NativeTokenSendingFailure();

        // _ARGS_HAS_TARGET = 1 << 251
        uint256 newTakerTraits = takerTraits | uint256(1 << 251);
        bytes memory argsMem = abi.encodePacked(computed, args);
        ILimitOrderProtocol(address(_LOP)).fillOrderArgs(order, r, vs, amount, newTakerTraits, argsMem);
    }

    /**
     * @notice Deploy destination chain escrow (original function)
     */
    function deployDst(IBaseEscrow.Immutables calldata dstImmutables, uint256 srcCancellationTimestamp) external onlyOwner payable {
        _FACTORY.createDstEscrow{value: msg.value}(dstImmutables, srcCancellationTimestamp);
    }

    /**
     * @notice Withdraw from escrow using secret
     */
    function withdraw(IEscrow escrow, bytes32 secret, IBaseEscrow.Immutables calldata immutables) external onlyOwner {
        escrow.withdraw(secret, immutables);
    }

    /**
     * @notice Cancel escrow
     */
    function cancel(IEscrow escrow, IBaseEscrow.Immutables calldata immutables) external onlyOwner {
        escrow.cancel(immutables);
    }

    /**
     * @notice Make arbitrary calls  
     */
    function arbitraryCalls(address[] calldata targets, bytes[] calldata arguments) external onlyOwner {
        uint256 length = targets.length;
        if (targets.length != arguments.length) revert LengthMismatch();
        for (uint256 i = 0; i < length; ++i) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = targets[i].call(arguments[i]);
            if (!success) RevertReasonForwarder.reRevert();
        }
    }

    // === Utility Functions === //

    /**
     * @notice Helper to create properly formatted extraData
     * @param dstVM Destination VM type
     * @param dstChainId Destination chain ID
     * @param dstAddress Destination address
     * @return extraData Encoded data for cross-chain swap
     */
    function createExtraData(
        uint8 dstVM,
        uint256 dstChainId,
        string calldata dstAddress
    ) external pure returns (bytes memory extraData) {
        return abi.encodePacked(dstVM, dstChainId, bytes(dstAddress));
    }

    /**
     * @notice Get factory address
     */
    function getFactory() external view returns (address) {
        return address(_FACTORY);
    }

    /**
     * @notice Get limit order protocol address
     */
    function getLimitOrderProtocol() external view returns (address) {
        return address(_LOP);
    }
}
