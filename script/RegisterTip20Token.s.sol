// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20LimitedMinter} from "../src/Tip20LimitedMinter.sol";

contract RegisterTip20Token is Script {
    function run(address wallet) public {
        address limitedMinterAddress = vm.envAddress("TIP20_LIMITED_MINTER");
        address token = vm.envAddress("TIP20_TOKEN");
        address mintDestination = vm.envAddress("MINT_DESTINATION");
        uint256 dailyMaxMint = vm.envUint("DAILY_MAX_MINT");

        console2.log("--------------------------------");
        console2.log("Registering TIP-20 token in Tip20LimitedMinter:");
        console2.log("Limited Minter:", limitedMinterAddress);
        console2.log("Token:", token);
        console2.log("Mint Destination:", mintDestination);
        console2.log("Daily Max Mint:", dailyMaxMint);
        console2.log("Caller:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        Tip20LimitedMinter(limitedMinterAddress).registerToken(token, mintDestination, dailyMaxMint);
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("TIP-20 token registered");
        console2.log("--------------------------------");
    }
}
