// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IOrderMixin } from "./interfaces/IOrderMixin.sol";
import { TakerTraits } from "./libraries/TakerTraitsLib.sol";
import { RevertReasonForwarder } from "solidity-utils/contracts/libraries/RevertReasonForwarder.sol";
import { IEscrowFactory } from "./interfaces/IEscrowFactory.sol";
import { IBaseEscrow } from "./interfaces/IBaseEscrow.sol";
import { TimelocksLib, Timelocks } from "./libraries/TimelocksLib.sol";
import { Address } from "solidity-utils/contracts/libraries/AddressLib.sol";
import { IEscrow } from "./interfaces/IEscrow.sol";
import { ImmutablesLib } from "./libraries/ImmutablesLib.sol";

/**
 * @title Simple Resolver contract for cross-chain swap (No KYC)
 * @notice Simplified resolver without KYC requirements
 * @custom:security-contact security@1inch.io
 */
contract SimpleResolver is Ownable {
    using ImmutablesLib for IBaseEscrow.Immutables;
    using TimelocksLib for Timelocks;

    error InvalidLength();
    error LengthMismatch();

    IEscrowFactory private immutable _FACTORY;
    IOrderMixin private immutable _LOP;

    constructor(IEscrowFactory factory, IOrderMixin lop, address initialOwner) Ownable(initialOwner) {
        _FACTORY = factory;
        _LOP = lop;
    }

    receive() external payable {} // solhint-disable-line no-empty-blocks

    /**
     * @notice Deploy source escrow by filling order
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
        // takerTraits = TakerTraits.wrap(TakerTraits.unwrap(takerTraits) | uint256(1 << 251));
        bytes memory argsMem = abi.encodePacked(computed, args);
        _LOP.fillOrderArgs(order, r, vs, amount, takerTraits, argsMem);
    }

    /**
     * @notice Deploy destination escrow
     */
    function deployDst(IBaseEscrow.Immutables calldata dstImmutables, uint256 srcCancellationTimestamp) external onlyOwner payable {
        _FACTORY.createDstEscrow{value: msg.value}(dstImmutables, srcCancellationTimestamp);
    }

    /**
     * @notice Withdraw from escrow
     */
    function withdraw(IEscrow escrow, bytes32 secret, IBaseEscrow.Immutables calldata immutables) external {
        escrow.withdraw(secret, immutables);
    }

    /**
     * @notice Cancel escrow
     */
    function cancel(IEscrow escrow, IBaseEscrow.Immutables calldata immutables) external {
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
}
