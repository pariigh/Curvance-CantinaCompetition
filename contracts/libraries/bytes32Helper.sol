// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20 } from "contracts/interfaces/IERC20.sol";

library BytesLib {

    /// ERRORS ///

    error BytesLib__ZeroLengthString();

    /// INTERNAL FUNCTIONS ///

    function _toBytes32WithETH(address tokenAddress) internal view returns (bytes32) {
        string memory concatString = string.concat(_getSymbol(tokenAddress), "/ETH");
        return _stringToBytes32(concatString);
    }

    function _toBytes32WithUSD(address tokenAddress) internal view returns (bytes32) {
        string memory concatString = string.concat(_getSymbol(tokenAddress), "/USD");
        return _stringToBytes32(concatString);
    }

    function _getSymbol(address tokenAddress) internal view returns (string memory) {
        return IERC20(tokenAddress).symbol();
    }

    /// @dev This will trim the output value to 32 bytes,
    ///      even if the bytes value is > 32 bytes
    function _stringToBytes32(string memory stringData) public pure returns (bytes32 result) {
        bytes memory bytesData = bytes(stringData);
        if (bytesData.length == 0) {
            revert BytesLib__ZeroLengthString();
        }

        /// @solidity memory-safe-assembly
        assembly {
            result := mload(add(stringData, 32))
        }
    }

}
