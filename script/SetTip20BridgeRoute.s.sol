// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20BridgeDeposit} from "../src/Tip20BridgeDeposit.sol";

contract SetTip20BridgeRoute is Script {
    function run(address wallet) public {
        address bridgeDeposit = vm.envAddress("TIP20_BRIDGE_DEPOSIT");
        address token = vm.envAddress("TIP20_TOKEN");
        uint256 destChainId = vm.envUint("DEST_CHAIN_ID");
        bool enabled = vm.envBool("ROUTE_ENABLED");
        uint256 fixedFee = vm.envUint("FIXED_FEE");

        uint256[] memory destChainIds = new uint256[](1);
        destChainIds[0] = destChainId;

        console2.log("--------------------------------");
        console2.log("Setting TIP-20 bridge route:");
        console2.log("Bridge Deposit:", bridgeDeposit);
        console2.log("Token:", token);
        console2.log("Destination Chain ID:", destChainId);
        console2.log("Enabled:", enabled);
        console2.log("Fixed Fee:", fixedFee);
        console2.log("Caller:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        Tip20BridgeDeposit(bridgeDeposit).setBridgeRoutes(token, destChainIds, enabled, fixedFee);
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("TIP-20 bridge route updated");
        console2.log("--------------------------------");
    }
}
