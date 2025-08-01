// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title MakerTraits
 * @notice A library to manage maker traits
 */
library MakerTraitsLib {
    uint256 private constant _NO_PARTIAL_FILLS_FLAG = 1 << 255;
    uint256 private constant _ALLOW_MULTIPLE_FILLS_FLAG = 1 << 254;

    function allowPartialFills(uint256 makerTraits) internal pure returns (bool) {
        return (makerTraits & _NO_PARTIAL_FILLS_FLAG) == 0;
    }

    function allowMultipleFills(uint256 makerTraits) internal pure returns (bool) {
        return (makerTraits & _ALLOW_MULTIPLE_FILLS_FLAG) != 0;
    }

    function isExpired(uint256 makerTraits) internal view returns (bool) {
        uint256 expiration = (makerTraits >> 80) & 0xffffffffff;
        return expiration != 0 && expiration < block.timestamp;
    }

    function isAllowedSender(uint256 makerTraits, address sender) internal pure returns (bool) {
        uint256 allowedSender = makerTraits & 0xffffffffffffffffff;
        return allowedSender == 0 || (uint256(uint160(sender)) & 0xffffffffffffffffff) == allowedSender;
    }

    function needCheckEpochManager(uint256 makerTraits) internal pure returns (bool) {
        return (makerTraits & (1 << 250)) != 0;
    }

    function useBitInvalidator(uint256 makerTraits) internal pure returns (bool) {
        return !allowPartialFills(makerTraits) || !allowMultipleFills(makerTraits);
    }

    function unwrapWeth(uint256 makerTraits) internal pure returns (bool) {
        return (makerTraits & (1 << 247)) != 0;
    }

    function usePermit2(uint256 makerTraits) internal pure returns (bool) {
        return (makerTraits & (1 << 248)) != 0;
    }

    function needPreInteractionCall(uint256 makerTraits) internal pure returns (bool) {
        return (makerTraits & (1 << 252)) != 0;
    }

    function needPostInteractionCall(uint256 makerTraits) internal pure returns (bool) {
        return (makerTraits & (1 << 251)) != 0;
    }

    function nonceOrEpoch(uint256 makerTraits) internal pure returns (uint256) {
        return (makerTraits >> 120) & 0xffffffffff;
    }

    function series(uint256 makerTraits) internal pure returns (uint256) {
        return (makerTraits >> 160) & 0xffffffffff;
    }
}
