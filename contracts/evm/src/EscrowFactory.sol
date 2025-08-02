// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IOrderMixin } from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import { BaseExtension } from "./extensions/BaseExtension.sol";
import { MultiVMResolverExtension } from "./extensions/MultiVMResolverExtension.sol";

import { ProxyHashLib } from "cross-chain-swap/libraries/ProxyHashLib.sol";
import { EscrowDst } from "cross-chain-swap/EscrowDst.sol";
import { EscrowSrc } from "cross-chain-swap/EscrowSrc.sol";
import { MerkleStorageInvalidator } from "cross-chain-swap/MerkleStorageInvalidator.sol";

import { Address, AddressLib } from "solidity-utils/contracts/libraries/AddressLib.sol";
import { Clones } from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import { Create2 } from "openzeppelin-contracts/contracts/utils/Create2.sol";
import { SafeERC20 } from "solidity-utils/contracts/libraries/SafeERC20.sol";

import { ImmutablesLib } from "cross-chain-swap/libraries/ImmutablesLib.sol";
import { Timelocks, TimelocksLib } from "cross-chain-swap/libraries/TimelocksLib.sol";
import { IEscrowFactory } from "cross-chain-swap/interfaces/IEscrowFactory.sol";
import { IBaseEscrow } from "cross-chain-swap/interfaces/IBaseEscrow.sol";
import { SRC_IMMUTABLES_LENGTH } from "cross-chain-swap/EscrowFactoryContext.sol";
import { MakerTraitsLib } from "limit-order-protocol/contracts/libraries/MakerTraitsLib.sol";

/**
 * @title Escrow Factory with Multi-VM Support
 * @notice Contract to create escrow contracts for cross-chain atomic swap with multi-VM resolver support
 */
contract EscrowFactory is IEscrowFactory, BaseExtension, MultiVMResolverExtension, MerkleStorageInvalidator {

    using AddressLib for Address;
    using Clones for address;
    using ImmutablesLib for IBaseEscrow.Immutables;
    using SafeERC20 for IERC20;
    using TimelocksLib for Timelocks;

    /// @notice See {IEscrowFactory-ESCROW_SRC_IMPLEMENTATION}.
    address public immutable ESCROW_SRC_IMPLEMENTATION;
    /// @notice See {IEscrowFactory-ESCROW_DST_IMPLEMENTATION}.
    address public immutable ESCROW_DST_IMPLEMENTATION;
    bytes32 internal immutable _PROXY_SRC_BYTECODE_HASH;
    bytes32 internal immutable _PROXY_DST_BYTECODE_HASH;

    constructor(
        address limitOrderProtocol,
        IERC20 feeToken,
        IERC20 accessToken,
        address owner,
        uint32 rescueDelaySrc,
        uint32 rescueDelayDst
    )
    BaseExtension(limitOrderProtocol) 
    MultiVMResolverExtension()
    MerkleStorageInvalidator(limitOrderProtocol) {
        ESCROW_SRC_IMPLEMENTATION = address(new EscrowSrc(rescueDelaySrc, accessToken));
        ESCROW_DST_IMPLEMENTATION = address(new EscrowDst(rescueDelayDst, accessToken));
        _PROXY_SRC_BYTECODE_HASH = ProxyHashLib.computeProxyBytecodeHash(ESCROW_SRC_IMPLEMENTATION);
        _PROXY_DST_BYTECODE_HASH = ProxyHashLib.computeProxyBytecodeHash(ESCROW_DST_IMPLEMENTATION);
    }

    /**
     * @notice Creates a new escrow contract for maker on the source chain.
     * @dev The caller must be whitelisted and pre-send the safety deposit in a native token
     * to a pre-computed deterministic address of the created escrow.
     * The external postInteraction function call will be made from the Limit Order Protocol
     * after all funds have been transferred. See {IPostInteraction-postInteraction}.
     * `extraData` consists of:
     *   - MultiVM extension data (handled by parent)
     *   - ExtraDataArgs struct (160 bytes)
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
    ) internal override(BaseExtension, MultiVMResolverExtension) {
        // First call parent for MultiVM extension logic
        uint256 superArgsLength = extraData.length - SRC_IMMUTABLES_LENGTH;
        super._postInteraction(
            order, extension, orderHash, taker, makingAmount, takingAmount, remainingMakingAmount, extraData[:superArgsLength]
        );

        // Parse ExtraDataArgs from the end of extraData
        ExtraDataArgs calldata extraDataArgs;
        assembly ("memory-safe") {
            extraDataArgs := add(extraData.offset, superArgsLength)
        }

        // Handle hashlock (single secret or merkle tree)
        bytes32 hashlock;
        if (MakerTraitsLib.allowMultipleFills(order.makerTraits)) {
            uint256 partsAmount = uint256(extraDataArgs.hashlockInfo) >> 240;
            if (partsAmount < 2) revert InvalidSecretsAmount();
            bytes32 key = keccak256(abi.encodePacked(orderHash, uint240(uint256(extraDataArgs.hashlockInfo))));
            ValidationData memory validated = lastValidated[key];
            hashlock = validated.leaf;
            if (!_isValidPartialFill(makingAmount, remainingMakingAmount, order.makingAmount, partsAmount, validated.index)) {
                revert InvalidPartialFill();
            }
        } else {
            hashlock = extraDataArgs.hashlockInfo;
        }

        // Create immutables for source chain escrow
        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            hashlock: hashlock,
            maker: order.maker,
            taker: Address.wrap(uint160(taker)),
            token: order.makerAsset,
            amount: makingAmount,
            safetyDeposit: extraDataArgs.deposits >> 128, // Upper 128 bits
            timelocks: extraDataArgs.timelocks.setDeployedAt(block.timestamp)
        });

        // Create destination chain complement data
        DstImmutablesComplement memory immutablesComplement = DstImmutablesComplement({
            maker: order.receiver.get() == address(0) ? order.maker : order.receiver,
            amount: takingAmount,
            token: extraDataArgs.dstToken,
            safetyDeposit: extraDataArgs.deposits & type(uint128).max, // Lower 128 bits
            chainId: extraDataArgs.dstChainId
        });

        // Emit event for off-chain processing
        emit SrcEscrowCreated(immutables, immutablesComplement);

        // Actually deploy the escrow contract
        bytes32 salt = immutables.hashMem();
        address escrow = _deployEscrow(salt, 0, ESCROW_SRC_IMPLEMENTATION);
        
        // Validate that the escrow has sufficient deposits
        if (escrow.balance < immutables.safetyDeposit) {
            revert InsufficientEscrowBalance();
        }
        
        // Validate that the escrow has the correct token amount
        if (IERC20(order.makerAsset.get()).safeBalanceOf(escrow) < makingAmount) {
            revert InsufficientEscrowBalance();
        }
    }

    /**
     * @notice See {IEscrowFactory-createDstEscrow}.
     */
    function createDstEscrow(IBaseEscrow.Immutables calldata dstImmutables, uint256 srcCancellationTimestamp) external payable {
        address token = dstImmutables.token.get();
        uint256 nativeAmount = dstImmutables.safetyDeposit;
        if (token == address(0)) {
            nativeAmount += dstImmutables.amount;
        }
        if (msg.value != nativeAmount) revert InsufficientEscrowBalance();

        IBaseEscrow.Immutables memory immutables = dstImmutables;
        immutables.timelocks = immutables.timelocks.setDeployedAt(block.timestamp);
        // Check that the escrow cancellation will start not later than the cancellation time on the source chain.
        if (immutables.timelocks.get(TimelocksLib.Stage.DstCancellation) > srcCancellationTimestamp) revert InvalidCreationTime();

        bytes32 salt = immutables.hashMem();
        address escrow = _deployEscrow(salt, msg.value, ESCROW_DST_IMPLEMENTATION);
        if (token != address(0)) {
            IERC20(token).safeTransferFrom(msg.sender, escrow, immutables.amount);
        }

        emit DstEscrowCreated(escrow, dstImmutables.hashlock, dstImmutables.taker);
    }

    /**
     * @notice See {IEscrowFactory-addressOfEscrowSrc}.
     */
    function addressOfEscrowSrc(IBaseEscrow.Immutables calldata immutables) external view virtual returns (address) {
        return Create2.computeAddress(immutables.hash(), _PROXY_SRC_BYTECODE_HASH);
    }

    /**
     * @notice See {IEscrowFactory-addressOfEscrowDst}.
     */
    function addressOfEscrowDst(IBaseEscrow.Immutables calldata immutables) external view virtual returns (address) {
        return Create2.computeAddress(immutables.hash(), _PROXY_DST_BYTECODE_HASH);
    }

    /**
     * @notice Deploys a new escrow contract.
     * @param salt The salt for the deterministic address computation.
     * @param value The value to be sent to the escrow contract.
     * @param implementation Address of the implementation.
     * @return escrow The address of the deployed escrow contract.
     */
    function _deployEscrow(bytes32 salt, uint256 value, address implementation) internal virtual returns (address escrow) {
        escrow = implementation.cloneDeterministic(salt, value);
    }

    function _isValidPartialFill(
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        uint256 orderMakingAmount,
        uint256 partsAmount,
        uint256 validatedIndex
    ) internal pure returns (bool) {
        uint256 calculatedIndex = (orderMakingAmount - remainingMakingAmount + makingAmount - 1) * partsAmount / orderMakingAmount;

        if (remainingMakingAmount == makingAmount) {
            // If the order is filled to completion, a secret with index i + 1 must be used
            // where i is the index of the secret for the last part.
            return (calculatedIndex + 2 == validatedIndex);
        } else if (orderMakingAmount != remainingMakingAmount) {
            // Calculate the previous fill index only if this is not the first fill.
            uint256 prevCalculatedIndex = (orderMakingAmount - remainingMakingAmount - 1) * partsAmount / orderMakingAmount;
            if (calculatedIndex == prevCalculatedIndex) return false;
        }

        return calculatedIndex + 1 == validatedIndex;
    }
}
