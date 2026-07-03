// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ITip20LimitedMinterBridge, Tip20BridgeDeposit} from "../src/Tip20BridgeDeposit.sol";

contract DeployTip20BridgeDeposit is Script {
    function run(address wallet) public returns (address) {
        address bridgeAdmin = vm.envAddress("BRIDGE_ADMIN");
        address limitedMinter = vm.envAddress("TIP20_LIMITED_MINTER_BRIDGE");
        address feeCollector = vm.envOr("FEE_COLLECTOR", address(0));

        console2.log("--------------------------------");
        console2.log("Deploying Tip20BridgeDeposit:");
        console2.log("Bridge Admin:", bridgeAdmin);
        console2.log("Tip20LimitedMinterBridge:", limitedMinter);
        console2.log("Fee Collector:", feeCollector);
        console2.log("Deployer:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        Tip20BridgeDeposit bridgeDeposit =
            new Tip20BridgeDeposit(bridgeAdmin, ITip20LimitedMinterBridge(limitedMinter), feeCollector);
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("Tip20BridgeDeposit deployed at:", address(bridgeDeposit));
        console2.log("--------------------------------");

        return address(bridgeDeposit);
    }
}
