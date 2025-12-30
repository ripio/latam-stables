// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LimitedMinterBridge} from "../../src/LimitedMinterBridge.sol";
import {BridgeDeposit} from "../../src/BridgeDeposit.sol";

/**
 * @title VerifyDeployment
 * @notice Verifies the deployment status of LimitedMinterBridge and BridgeDeposit.
 * @dev
 *  - Checks if contracts are deployed at expected addresses.
 *  - Verifies role configuration.
 *  - Checks if BridgeDeposit is linked to the correct LimitedMinterBridge.
 *
 * Environment variables:
 *  - LIMITED_MINTER_BRIDGE: Expected LimitedMinterBridge address
 *  - BRIDGE_DEPOSIT: Expected BridgeDeposit address
 */
contract VerifyDeployment is Script {
    function run() public view {
        address limitedMinterAddr = vm.envAddress("LIMITED_MINTER_BRIDGE");
        address bridgeDepositAddr = vm.envAddress("BRIDGE_DEPOSIT");

        console2.log("================================");
        console2.log("Verifying Deployment");
        console2.log("================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("--------------------------------");

        bool allOk = true;

        // Check LimitedMinterBridge
        console2.log("LimitedMinterBridge:", limitedMinterAddr);
        if (limitedMinterAddr.code.length == 0) {
            console2.log("  [ERROR] Not deployed");
            allOk = false;
        } else {
            console2.log("  [OK] Deployed");

            LimitedMinterBridge lmb = LimitedMinterBridge(limitedMinterAddr);
            bytes32 minterRole = lmb.MINTER_ROLE();

            // Check if BridgeDeposit has MINTER_ROLE
            if (lmb.hasRole(minterRole, bridgeDepositAddr)) {
                console2.log("  [OK] BridgeDeposit has MINTER_ROLE");
            } else {
                console2.log("  [WARNING] BridgeDeposit missing MINTER_ROLE");
                console2.log("       Run: make grant-bridge-minter-role");
            }
        }

        console2.log("--------------------------------");

        // Check BridgeDeposit
        console2.log("BridgeDeposit:", bridgeDepositAddr);
        if (bridgeDepositAddr.code.length == 0) {
            console2.log("  [ERROR] Not deployed");
            allOk = false;
        } else {
            console2.log("  [OK] Deployed");

            BridgeDeposit bd = BridgeDeposit(bridgeDepositAddr);
            address linkedMinter = address(bd.limitedMinter());

            if (linkedMinter == limitedMinterAddr) {
                console2.log("  [OK] Linked to correct LimitedMinterBridge");
            } else {
                console2.log("  [ERROR] Linked to wrong LimitedMinterBridge");
                console2.log("       Expected:", limitedMinterAddr);
                console2.log("       Actual:", linkedMinter);
                allOk = false;
            }
        }

        console2.log("================================");
        if (allOk) {
            console2.log("All checks passed!");
        } else {
            console2.log("Some checks failed. See errors above.");
        }
        console2.log("================================");
    }
}
