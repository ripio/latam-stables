// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LimitedMinterBridge} from "../../src/LimitedMinterBridge.sol";

/**
 * @title GrantMinterRole
 * @notice Grants MINTER_ROLE on LimitedMinterBridge to BridgeDeposit after deployment.
 * @dev
 *  - Run this after deploying both contracts via DeployBridgeCreate2.s.sol.
 *  - Must be called by an address with DEFAULT_ADMIN_ROLE on LimitedMinterBridge.
 *
 * Environment variables:
 *  - LIMITED_MINTER_BRIDGE: Deployed LimitedMinterBridge address
 *  - BRIDGE_DEPOSIT: Deployed BridgeDeposit address
 */
contract GrantMinterRole is Script {
    function run(address wallet) public {
        address limitedMinterAddr = vm.envAddress("LIMITED_MINTER_BRIDGE");
        address bridgeDepositAddr = vm.envAddress("BRIDGE_DEPOSIT");

        LimitedMinterBridge limitedMinter = LimitedMinterBridge(limitedMinterAddr);
        bytes32 minterRole = limitedMinter.MINTER_ROLE();

        console2.log("================================");
        console2.log("Granting MINTER_ROLE to BridgeDeposit");
        console2.log("================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("LimitedMinterBridge:", limitedMinterAddr);
        console2.log("BridgeDeposit:", bridgeDepositAddr);
        console2.log("Caller:", wallet);
        console2.log("--------------------------------");

        // Check if role already granted
        if (limitedMinter.hasRole(minterRole, bridgeDepositAddr)) {
            console2.log("MINTER_ROLE already granted to BridgeDeposit");
            console2.log("No action needed.");
            console2.log("================================");
            return;
        }

        vm.startBroadcast(wallet);

        limitedMinter.grantRole(minterRole, bridgeDepositAddr);

        vm.stopBroadcast();

        console2.log("MINTER_ROLE granted successfully!");
        console2.log("================================");
        console2.log("");
        console2.log("REMAINING STEPS:");
        console2.log("1. Grant MINTER_ROLE on LatamStable to LimitedMinterBridge");
        console2.log("2. Register token in LimitedMinterBridge");
        console2.log("3. Enable bridge routes in BridgeDeposit");
        console2.log("================================");
    }
}
