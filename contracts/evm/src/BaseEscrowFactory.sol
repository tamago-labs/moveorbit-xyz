// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Clones } from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "openzeppelin-contracts/contracts/utils/Create2.sol"; 
import { SafeERC20 } from "solidity-utils/contracts/libraries/SafeERC20.sol";

import { IOrderMixin } from "./interfaces/IOrderMixin.sol";
import { MakerTraitsLib } from "./libraries/MakerTraitsLib.sol"; 

import { ImmutablesLib } from "./libraries/ImmutablesLib.sol";
import { Timelocks, TimelocksLib } from "./libraries/TimelocksLib.sol";

import { IEscrowFactory } from "./interfaces/IEscrowFactory.sol";
import { IBaseEscrow } from "./interfaces/IBaseEscrow.sol";
import { SRC_IMMUTABLES_LENGTH } from "./EscrowFactoryContext.sol";

/**
 * @title Abstract contract for escrow factory
 * @notice Contract to create escrow contracts for cross-chain atomic swap.
 * @custom:security-contact security@1inch.io
 */
abstract contract BaseEscrowFactory is IEscrowFactory { 
    using Clones for address;
    using ImmutablesLib for IBaseEscrow.Immutables;
    using SafeERC20 for IERC20;
    using TimelocksLib for Timelocks;

    /// @notice See {IEscrowFactory-ESCROW_SRC_IMPLEMENTATION}.
    address public immutable ESCROW_SRC_IMPLEMENTATION;
    /// @notice See {IEscrowFactory-ESCROW_DST_IMPLEMENTATION}.
    address public immutable ESCROW_DST_IMPLEMENTATION;
    
    // Storage for non-immutable state
    address internal _LIMIT_ORDER_PROTOCOL;
    IERC20 internal _FEE_TOKEN;
    IERC20 internal _ACCESS_TOKEN;
    
    bytes32 internal immutable _PROXY_SRC_BYTECODE_HASH;
    bytes32 internal immutable _PROXY_DST_BYTECODE_HASH;

    // Validation storage for partial fills
    struct ValidationData {
        bytes32 leaf;
        uint256 index;
    }
    mapping(bytes32 => ValidationData) public lastValidated;

    /**
     * @notice Creates a new escrow contract for maker on the source chain.
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
    ) internal {
        ExtraDataArgs calldata extraDataArgs;
        assembly ("memory-safe") {
            extraDataArgs := extraData.offset
        }

        bytes32 hashlock = extraDataArgs.hashlockInfo;

        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: orderHash,
            hashlock: hashlock,
            maker: order.maker,
            taker: taker,
            token: order.makerAsset,
            amount: makingAmount,
            safetyDeposit: extraDataArgs.deposits >> 128,
            timelocks: extraDataArgs.timelocks.setDeployedAt(block.timestamp)
        });

        DstImmutablesComplement memory immutablesComplement = DstImmutablesComplement({
            maker: order.receiver == address(0) ? order.maker : order.receiver,
            amount: takingAmount,
            token: extraDataArgs.dstToken,
            safetyDeposit: extraDataArgs.deposits & type(uint128).max,
            chainId: extraDataArgs.dstChainId
        });

        emit SrcEscrowCreated(immutables, immutablesComplement);

        bytes32 salt = immutables.hashMem();
        address escrow = _deployEscrow(salt, 0, ESCROW_SRC_IMPLEMENTATION);
        if (escrow.balance < immutables.safetyDeposit || IERC20(order.makerAsset).balanceOf(escrow) < makingAmount) {
            revert InsufficientEscrowBalance();
        }
    }

    /**
     * @notice See {IEscrowFactory-createDstEscrow}.
     */
    function createDstEscrow(IBaseEscrow.Immutables calldata dstImmutables, uint256 srcCancellationTimestamp) external payable {
        address token = dstImmutables.token;
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
}
