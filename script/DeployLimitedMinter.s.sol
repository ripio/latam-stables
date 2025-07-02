// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LimitedMinter} from "../src/LimitedMinter.sol";

contract DeployLimitedMinter is Script {
    function run(address wallet) public returns (address) {
        address deployer = wallet;

        // Define initialization parameters
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
        address minter = vm.envAddress("MINTER");

        // Log parameter values
        console2.log("--------------------------------");
        console2.log("Deploying LimitedMinter with the following parameters:");
        console2.log("Default Admin:", defaultAdmin);
        console2.log("Minter:", minter);
        console2.log("Deployer:", deployer);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);

        // Deploy the LimitedMinter contract
        LimitedMinter limitedMinter = new LimitedMinter(defaultAdmin, minter);

        address limitedMinterAddress = address(limitedMinter);

        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("LimitedMinter deployed at:", limitedMinterAddress);
        console2.log("Deployer:", deployer);
        console2.log("Default Admin:", defaultAdmin);
        console2.log("Minter:", minter);
        console2.log("Contract deployed successfully");
        console2.log("--------------------------------");
        
        return limitedMinterAddress;
    }
}
