// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20LimitedMinter} from "../src/Tip20LimitedMinter.sol";

contract Tip20Mint is Script {
    function run(address wallet) public {
        address limitedMinterAddress = vm.envAddress("TIP20_LIMITED_MINTER");
        address token = vm.envAddress("TIP20_TOKEN");
        uint256 amount = vm.envUint("MINT_AMOUNT");
        bytes32 memo = vm.envOr("MINT_MEMO", bytes32(0));

        console2.log("--------------------------------");
        console2.log("Minting TIP-20 through Tip20LimitedMinter:");
        console2.log("Limited Minter:", limitedMinterAddress);
        console2.log("Token:", token);
        console2.log("Amount:", amount);
        console2.logBytes32(memo);
        console2.log("Caller:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        if (memo == bytes32(0)) {
            Tip20LimitedMinter(limitedMinterAddress).mint(token, amount);
        } else {
            Tip20LimitedMinter(limitedMinterAddress).mintWithMemo(token, amount, memo);
        }
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("TIP-20 mint complete");
        console2.log("--------------------------------");
    }
}
