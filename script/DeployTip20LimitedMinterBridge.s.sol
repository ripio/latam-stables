// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20LimitedMinterBridge} from "../src/Tip20LimitedMinterBridge.sol";

contract DeployTip20LimitedMinterBridge is Script {
    function run(address wallet) public returns (address) {
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
        address minter = vm.envAddress("MINTER");
        address configAdmin = vm.envOr("TOKEN_CONFIG_ADMIN", defaultAdmin);

        console2.log("--------------------------------");
        console2.log("Deploying Tip20LimitedMinterBridge:");
        console2.log("Default Admin:", defaultAdmin);
        console2.log("Minter:", minter);
        console2.log("Token Config Admin:", configAdmin);
        console2.log("Deployer:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        Tip20LimitedMinterBridge limitedMinterBridge = new Tip20LimitedMinterBridge(defaultAdmin, minter, configAdmin);
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("Tip20LimitedMinterBridge deployed at:", address(limitedMinterBridge));
        console2.log("--------------------------------");

        return address(limitedMinterBridge);
    }
}
