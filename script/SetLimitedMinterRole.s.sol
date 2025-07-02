// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LatamStable} from "../src/LatamStable.sol";

contract SetLimitedMinterRole is Script {
    function run(address wallet) public {
        address deployer = wallet;

        // Read addresses from environment variables
        address latamStableAddress = vm.envAddress("LATAM_STABLE_ADDRESS");
        address limitedMinterAddress = vm.envAddress("LIMITED_MINTER_ADDRESS");

        // Get the LatamStable contract instance
        LatamStable latamStable = LatamStable(latamStableAddress);

        // Log parameter values
        console2.log("--------------------------------");
        console2.log("Setting LimitedMinter as minter for LatamStable with the following parameters:");
        console2.log("LatamStable Address:", latamStableAddress);
        console2.log("LimitedMinter Address:", limitedMinterAddress);
        console2.log("Admin Wallet:", deployer);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);

        // Grant MINTER_ROLE to the LimitedMinter contract
        bytes32 minterRole = latamStable.MINTER_ROLE();
        latamStable.grantRole(minterRole, limitedMinterAddress);

        vm.stopBroadcast();

        // Verify the role was granted
        bool hasRole = latamStable.hasRole(minterRole, limitedMinterAddress);

        console2.log("--------------------------------");
        console2.log("MINTER_ROLE granted successfully:", hasRole);
        console2.log("LimitedMinter can now mint tokens for LatamStable");
        console2.log("LatamStable Address:", latamStableAddress);
        console2.log("LimitedMinter Address:", limitedMinterAddress);
        console2.log("Role granted by:", deployer);
        console2.log("--------------------------------");
    }
} 