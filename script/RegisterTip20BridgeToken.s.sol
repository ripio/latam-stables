// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20LimitedMinterBridge} from "../src/Tip20LimitedMinterBridge.sol";

contract RegisterTip20BridgeToken is Script {
    function run(address wallet) public {
        address limitedMinterBridge = vm.envAddress("TIP20_LIMITED_MINTER_BRIDGE");
        address token = vm.envAddress("TIP20_TOKEN");
        uint256 dailyMaxMint = vm.envUint("DAILY_MAX_MINT");

        console2.log("--------------------------------");
        console2.log("Registering TIP-20 bridge token:");
        console2.log("Limited Minter Bridge:", limitedMinterBridge);
        console2.log("Token:", token);
        console2.log("Daily Max Mint:", dailyMaxMint);
        console2.log("Caller:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        Tip20LimitedMinterBridge(limitedMinterBridge).registerToken(token, dailyMaxMint);
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("TIP-20 bridge token registered");
        console2.log("--------------------------------");
    }
}
