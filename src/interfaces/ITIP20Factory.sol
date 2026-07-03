// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITIP20} from "./ITIP20.sol";

interface ITIP20Factory {
    function createToken(
        string memory name,
        string memory symbol,
        string memory currency,
        ITIP20 quoteToken,
        address admin,
        bytes32 salt
    ) external returns (address token);

    function createToken(
        string memory name,
        string memory symbol,
        string memory currency,
        ITIP20 quoteToken,
        address admin,
        bytes32 salt,
        string memory logoURI
    ) external returns (address token);

    function isTIP20(address token) external view returns (bool);

    function getTokenAddress(address sender, bytes32 salt) external pure returns (address token);
}
