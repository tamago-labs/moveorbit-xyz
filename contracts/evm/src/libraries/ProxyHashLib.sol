// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Library for computing proxy bytecode hash
 * @custom:security-contact security@1inch.io
 */
library ProxyHashLib {
    /**
     * @notice Computes the bytecode hash of the proxy contract
     * @param implementation The implementation address
     * @return The bytecode hash
     */
    function computeProxyBytecodeHash(address implementation) internal pure returns (bytes32) {
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        return keccak256(bytecode);
    }
}
