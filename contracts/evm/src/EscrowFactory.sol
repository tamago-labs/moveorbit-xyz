// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IOrderMixin } from "limit-order-protocol/contracts/interfaces/IOrderMixin.sol";
import { BaseExtension } from "limit-order-settlement/contracts/extensions/BaseExtension.sol";
import { MultiVMResolverExtension } from "./extensions/MultiVMResolverExtension.sol";

import { ProxyHashLib } from "cross-chain-swap/libraries/ProxyHashLib.sol";
import { BaseEscrowFactory } from "cross-chain-swap/BaseEscrowFactory.sol";
import { EscrowDst } from "cross-chain-swap/EscrowDst.sol";
import { EscrowSrc } from "cross-chain-swap/EscrowSrc.sol";
import { MerkleStorageInvalidator } from "cross-chain-swap/MerkleStorageInvalidator.sol";

import { Address, AddressLib } from "solidity-utils/contracts/libraries/AddressLib.sol";
import { Clones } from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "openzeppelin-contracts/contracts/utils/Create2.sol";
import { SafeERC20 } from "solidity-utils/contracts/libraries/SafeERC20.sol";

import { ImmutablesLib } from "cross-chain-swap/libraries/ImmutablesLib.sol";
import { Timelocks, TimelocksLib } from "cross-chain-swap/libraries/TimelocksLib.sol";
import { IEscrowFactory } from "cross-chain-swap/interfaces/IEscrowFactory.sol";
import { IBaseEscrow } from "cross-chain-swap/interfaces/IBaseEscrow.sol";


/**
 * @title Escrow Factory with Multi-VM Support
 * @notice Contract to create escrow contracts for cross-chain atomic swap with multi-VM resolver support
 */

contract EscrowFactory is  BaseExtension, MultiVMResolverExtension, MerkleStorageInvalidator {

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
     * @notice Post-interaction that handles both validation and multi-VM tracking
     * @dev Resolves diamond inheritance by explicitly calling both parent implementations
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
        // First, call the MultiVMResolverExtension implementation
        // This handles cross-VM order creation and tracking
        MultiVMResolverExtension._postInteraction(
            order, extension, orderHash, taker, makingAmount, takingAmount, remainingMakingAmount, extraData
        );
        
        // Note: MultiVMResolverExtension._postInteraction already calls 
        // super._postInteraction(), which will invoke BaseExtension._postInteraction()
        // So we don't need to call BaseExtension._postInteraction() explicitly here
        // to avoid double execution
    }

}