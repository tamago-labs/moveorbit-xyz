// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title TakerTraits
 * @notice A library to manage taker traits
 */
type TakerTraits is uint256;

library TakerTraitsLib {
    uint256 private constant _MAKER_AMOUNT_FLAG = 1 << 255;
    uint256 private constant _UNWRAP_WETH_FLAG = 1 << 254;
    uint256 private constant _SKIP_ORDER_PERMIT_FLAG = 1 << 253;
    uint256 private constant _USE_PERMIT2_FLAG = 1 << 252;
    uint256 private constant _ARGS_HAS_TARGET = 1 << 251;

    uint256 private constant _ARGS_EXTENSION_LENGTH_OFFSET = 224;
    uint256 private constant _ARGS_EXTENSION_LENGTH_MASK = 0xff << _ARGS_EXTENSION_LENGTH_OFFSET;
    uint256 private constant _ARGS_INTERACTION_LENGTH_OFFSET = 200;
    uint256 private constant _ARGS_INTERACTION_LENGTH_MASK = 0xff << _ARGS_INTERACTION_LENGTH_OFFSET;

    function isMakingAmount(TakerTraits takerTraits) internal pure returns (bool) {
        return (TakerTraits.unwrap(takerTraits) & _MAKER_AMOUNT_FLAG) != 0;
    }

    function unwrapWeth(TakerTraits takerTraits) internal pure returns (bool) {
        return (TakerTraits.unwrap(takerTraits) & _UNWRAP_WETH_FLAG) != 0;
    }

    function skipMakerPermit(TakerTraits takerTraits) internal pure returns (bool) {
        return (TakerTraits.unwrap(takerTraits) & _SKIP_ORDER_PERMIT_FLAG) != 0;
    }

    function usePermit2(TakerTraits takerTraits) internal pure returns (bool) {
        return (TakerTraits.unwrap(takerTraits) & _USE_PERMIT2_FLAG) != 0;
    }

    function argsHasTarget(TakerTraits takerTraits) internal pure returns (bool) {
        return (TakerTraits.unwrap(takerTraits) & _ARGS_HAS_TARGET) != 0;
    }

    function argsExtensionLength(TakerTraits takerTraits) internal pure returns (uint256) {
        return (TakerTraits.unwrap(takerTraits) & _ARGS_EXTENSION_LENGTH_MASK) >> _ARGS_EXTENSION_LENGTH_OFFSET;
    }

    function argsInteractionLength(TakerTraits takerTraits) internal pure returns (uint256) {
        return (TakerTraits.unwrap(takerTraits) & _ARGS_INTERACTION_LENGTH_MASK) >> _ARGS_INTERACTION_LENGTH_OFFSET;
    }

    function threshold(TakerTraits takerTraits) internal pure returns (uint256) {
        return TakerTraits.unwrap(takerTraits) & ((1 << 184) - 1);
    }
}
