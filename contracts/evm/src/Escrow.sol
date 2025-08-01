// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import { BaseEscrow } from "./BaseEscrow.sol";
import { IBaseEscrow } from "./interfaces/IBaseEscrow.sol";
import { IEscrowFactory } from "./interfaces/IEscrowFactory.sol";
import { ImmutablesLib } from "./libraries/ImmutablesLib.sol";
import { ProxyHashLib } from "./libraries/ProxyHashLib.sol";
import { IEscrow } from "./interfaces/IEscrow.sol";

/**
 * @title Abstract Escrow contract for cross-chain atomic swap.
 * @custom:security-contact security@1inch.io
 */
abstract contract Escrow is BaseEscrow, IEscrow {
    using ImmutablesLib for IBaseEscrow.Immutables;

     /// @notice See {IEscrow-PROXY_BYTECODE_HASH}.
    bytes32 public immutable PROXY_BYTECODE_HASH = ProxyHashLib.computeProxyBytecodeHash(address(this));

    /**
     * @dev Should verify that the computed escrow address matches the address of this contract.
     */
    function _validateImmutables(IBaseEscrow.Immutables calldata immutables) internal view override {
        if (FACTORY != msg.sender && address(this) != _escrowAddress(immutables)) revert InvalidImmutables();
    }

    /**
     * @dev Computes the deterministic address of the escrow based on the immutables.
     * @param immutables The immutable arguments used to compute the address.
     * @return The computed address of the escrow.
     */
    function _escrowAddress(IBaseEscrow.Immutables calldata immutables) internal view virtual returns (address);
}
