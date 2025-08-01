// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "solidity-utils/contracts/libraries/SafeERC20.sol";
import { AddressLib, Address } from "solidity-utils/contracts/libraries/AddressLib.sol";

import { Timelocks, TimelocksLib } from "./libraries/TimelocksLib.sol";
import { ImmutablesLib } from "./libraries/ImmutablesLib.sol";

import { IEscrowSrc } from "./interfaces/IEscrowSrc.sol";
import { IEscrowFactory } from "./interfaces/IEscrowFactory.sol";
import { IBaseEscrow } from "./interfaces/IBaseEscrow.sol";
import { BaseEscrow } from "./BaseEscrow.sol";
import { Escrow } from "./Escrow.sol";

/**
 * @title Source Escrow contract for cross-chain atomic swap.
 * @notice Contract to initially lock funds and then unlock them with verification of the secret presented.
 * @custom:security-contact security@1inch.io
 */
contract EscrowSrc is Escrow, IEscrowSrc {
    using AddressLib for Address;
    using ImmutablesLib for IBaseEscrow.Immutables;
    using SafeERC20 for IERC20;
    using TimelocksLib for Timelocks;

    constructor(uint32 rescueDelay, IERC20 accessToken) BaseEscrow(rescueDelay, accessToken) {}

    /**
     * @notice See {IBaseEscrow-withdraw}.
     */
    function withdraw(bytes32 secret, IBaseEscrow.Immutables calldata immutables)
        external
        onlyTaker(immutables)
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.SrcWithdrawal))
        onlyBefore(immutables.timelocks.get(TimelocksLib.Stage.SrcCancellation))
    {
        _withdrawTo(secret, msg.sender, immutables);
    }

    /**
     * @notice See {IEscrowSrc-withdrawTo}.
     */
    function withdrawTo(bytes32 secret, address target, IBaseEscrow.Immutables calldata immutables)
        external
        onlyTaker(immutables)
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.SrcWithdrawal))
        onlyBefore(immutables.timelocks.get(TimelocksLib.Stage.SrcCancellation))
    {
        _withdrawTo(secret, target, immutables);
    }

    /**
     * @notice See {IEscrowSrc-publicWithdraw}.
     */
    function publicWithdraw(bytes32 secret, IBaseEscrow.Immutables calldata immutables)
        external
        onlyAccessTokenHolder()
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.SrcPublicWithdrawal))
        onlyBefore(immutables.timelocks.get(TimelocksLib.Stage.SrcCancellation))
    {
        _withdrawTo(secret, immutables.taker, immutables);
    }

    /**
     * @notice See {IBaseEscrow-cancel}.
     */
    function cancel(IBaseEscrow.Immutables calldata immutables)
        external
        onlyTaker(immutables)
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.SrcCancellation))
    {
        _cancel(immutables);
    }

    /**
     * @notice See {IEscrowSrc-publicCancel}.
     */
    function publicCancel(IBaseEscrow.Immutables calldata immutables)
        external
        onlyAccessTokenHolder()
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.SrcPublicCancellation))
    {
        _cancel(immutables);
    }

    /**
     * @dev Transfers ERC20 tokens to the target and native tokens to the caller.
     * @param secret The secret that unlocks the escrow.
     * @param target The address to transfer ERC20 tokens to.
     * @param immutables The immutable values used to deploy the clone contract.
     */
    function _withdrawTo(bytes32 secret, address target, IBaseEscrow.Immutables calldata immutables)
        internal
        onlyValidImmutables(immutables)
        onlyValidSecret(secret, immutables)
    {
        IERC20(immutables.token).safeTransfer(target, immutables.amount);
        _ethTransfer(msg.sender, immutables.safetyDeposit);
        emit EscrowWithdrawal(secret);
    }

    /**
     * @dev Transfers ERC20 tokens to the maker and native tokens to the caller.
     * @param immutables The immutable values used to deploy the clone contract.
     */
    function _cancel(IBaseEscrow.Immutables calldata immutables) internal onlyValidImmutables(immutables) {
        IERC20(immutables.token).safeTransfer(immutables.maker, immutables.amount);
        _ethTransfer(msg.sender, immutables.safetyDeposit);
        emit EscrowCancelled();
    }

    /**
     * @dev Computes the deterministic address of the escrow based on the immutables.
     */
    function _escrowAddress(IBaseEscrow.Immutables calldata immutables) internal view override returns (address) {
        return IEscrowFactory(FACTORY).addressOfEscrowSrc(immutables);
    }
}
