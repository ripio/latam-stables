// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LimitedMinterBridge} from "../src/LimitedMinterBridge.sol";

contract DeployLimitedMinterBridge is Script {
    function run(address wallet) public returns (address) {
        address deployer = wallet;

        // Define initialization parameters
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
        address minter = vm.envAddress("MINTER");

        // Log parameter values
        console2.log("--------------------------------");
        console2.log("Deploying LimitedMinterBridge with the following parameters:");
        console2.log("Default Admin:", defaultAdmin);
        console2.log("Minter:", minter);
        console2.log("Deployer:", deployer);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);

        // Deploy the LimitedMinterBridge contract
        LimitedMinterBridge limitedMinterBridge = new LimitedMinterBridge(
            defaultAdmin,
            minter
        );

        address limitedMinterBridgeAddress = address(limitedMinterBridge);

        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("LimitedMinterBridge deployed at:", limitedMinterBridgeAddress);
        console2.log("Deployer:", deployer);
        console2.log("Default Admin:", defaultAdmin);
        console2.log("Minter:", minter);
        console2.log("Contract deployed successfully");
        console2.log("--------------------------------");

        return limitedMinterBridgeAddress;
    }
}

