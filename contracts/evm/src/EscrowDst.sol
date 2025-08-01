// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "solidity-utils/contracts/libraries/SafeERC20.sol"; 

import { Timelocks, TimelocksLib } from "./libraries/TimelocksLib.sol";

import { IEscrowDst } from "./interfaces/IEscrowDst.sol";
import { IEscrowFactory } from "./interfaces/IEscrowFactory.sol";
import { IBaseEscrow } from "./interfaces/IBaseEscrow.sol";
import { BaseEscrow } from "./BaseEscrow.sol";
import { Escrow } from "./Escrow.sol";

/**
 * @title Destination Escrow contract for cross-chain atomic swap.
 * @notice Contract to initially lock funds and then unlock them with verification of the secret presented.
 * @custom:security-contact security@1inch.io
 */
contract EscrowDst is Escrow, IEscrowDst {
    using SafeERC20 for IERC20; 
    using TimelocksLib for Timelocks;

    constructor(uint32 rescueDelay, IERC20 accessToken) BaseEscrow(rescueDelay, accessToken) {}

    /**
     * @notice See {IBaseEscrow-withdraw}.
     */
    function withdraw(bytes32 secret, IBaseEscrow.Immutables calldata immutables)
        external
        onlyTaker(immutables)
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.DstWithdrawal))
        onlyBefore(immutables.timelocks.get(TimelocksLib.Stage.DstCancellation))
    {
        _withdraw(secret, immutables);
    }

    /**
     * @notice See {IEscrowDst-publicWithdraw}.
     */
    function publicWithdraw(bytes32 secret, IBaseEscrow.Immutables calldata immutables)
        external
        onlyAccessTokenHolder()
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.DstPublicWithdrawal))
        onlyBefore(immutables.timelocks.get(TimelocksLib.Stage.DstCancellation))
    {
        _withdraw(secret, immutables);
    }

    /**
     * @notice See {IBaseEscrow-cancel}.
     */
    function cancel(IBaseEscrow.Immutables calldata immutables)
        external
        onlyTaker(immutables)
        onlyValidImmutables(immutables)
        onlyAfter(immutables.timelocks.get(TimelocksLib.Stage.DstCancellation))
    {
        _uniTransfer(immutables.token, immutables.taker, immutables.amount);
        _ethTransfer(msg.sender, immutables.safetyDeposit);
        emit EscrowCancelled();
    }

    /**
     * @dev Transfers ERC20 (or native) tokens to the maker and native tokens to the caller.
     * @param immutables The immutable values used to deploy the clone contract.
     */
    function _withdraw(bytes32 secret, IBaseEscrow.Immutables calldata immutables)
        internal
        onlyValidImmutables(immutables)
        onlyValidSecret(secret, immutables)
    {
        _uniTransfer(immutables.token, immutables.maker, immutables.amount);
        _ethTransfer(msg.sender, immutables.safetyDeposit);
        emit EscrowWithdrawal(secret);
    }

    /**
     * @dev Computes the deterministic address of the escrow based on the immutables.
     */
    function _escrowAddress(IBaseEscrow.Immutables calldata immutables) internal view override returns (address) {
        return IEscrowFactory(FACTORY).addressOfEscrowDst(immutables);
    }
}
