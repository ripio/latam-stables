// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20LimitedMinterBridge} from "../src/Tip20LimitedMinterBridge.sol";

contract GrantTip20BridgeMinterRole is Script {
    function run(address wallet) public {
        address limitedMinterBridge = vm.envAddress("TIP20_LIMITED_MINTER_BRIDGE");
        address bridgeDeposit = vm.envAddress("TIP20_BRIDGE_DEPOSIT");

        Tip20LimitedMinterBridge minter = Tip20LimitedMinterBridge(limitedMinterBridge);

        console2.log("--------------------------------");
        console2.log("Granting Tip20LimitedMinterBridge MINTER_ROLE:");
        console2.log("Limited Minter Bridge:", limitedMinterBridge);
        console2.log("Bridge Deposit:", bridgeDeposit);
        console2.log("Caller/Admin:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        minter.grantRole(minter.MINTER_ROLE(), bridgeDeposit);
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("Bridge MINTER_ROLE grant complete");
        console2.log("--------------------------------");
    }
}
