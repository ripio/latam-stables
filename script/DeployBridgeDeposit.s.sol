// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BridgeDeposit, ILimitedMinterBridge} from "../src/BridgeDeposit.sol";

contract DeployBridgeDeposit is Script {
    function run(address wallet) public returns (address) {
        address deployer = wallet;

        // Env vars:
        // BRIDGE_ADMIN:      will receive DEFAULT_ADMIN_ROLE and BRIDGE_OPERATOR_ROLE
        // LIMITED_MINTER:    address of the already-deployed LimitedMinterBridge on this chain
        // FEE_COLLECTOR:     address that receives bridge fees (can be 0x0 if no fees)
        address bridgeAdmin = vm.envAddress("BRIDGE_ADMIN");
        address limitedMinter = vm.envAddress("LIMITED_MINTER");
        address feeCollector = vm.envOr("FEE_COLLECTOR", address(0));

        console2.log("--------------------------------");
        console2.log("Deploying BridgeDeposit with the following parameters:");
        console2.log("Bridge Admin:", bridgeAdmin);
        console2.log("LimitedMinterBridge:", limitedMinter);
        console2.log("Fee Collector:", feeCollector);
        console2.log("Deployer:", deployer);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);

        BridgeDeposit bridgeDeposit = new BridgeDeposit(
            bridgeAdmin,
            ILimitedMinterBridge(limitedMinter),
            feeCollector
        );

        address bridgeDepositAddress = address(bridgeDeposit);

        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("BridgeDeposit deployed at:", bridgeDepositAddress);
        console2.log("Deployer:", deployer);
        console2.log("Bridge Admin:", bridgeAdmin);
        console2.log("LimitedMinterBridge:", limitedMinter);
        console2.log("Fee Collector:", feeCollector);
        console2.log("Contract deployed successfully");
        console2.log("--------------------------------");

        return bridgeDepositAddress;
    }
}

