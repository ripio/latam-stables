// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20BridgeDeposit} from "../src/Tip20BridgeDeposit.sol";

contract Tip20DepositForBridge is Script {
    function run(address wallet) public returns (uint256 depositId) {
        address bridgeDeposit = vm.envAddress("TIP20_BRIDGE_DEPOSIT");
        address token = vm.envAddress("TIP20_TOKEN");
        uint256 amount = vm.envUint("BRIDGE_AMOUNT");
        uint256 destChainId = vm.envUint("DEST_CHAIN_ID");
        address destRecipient = vm.envAddress("DEST_RECIPIENT");
        bytes32 clientDepositId = vm.envOr("CLIENT_DEPOSIT_ID", bytes32(0));

        console2.log("--------------------------------");
        console2.log("Depositing TIP-20 for bridge:");
        console2.log("Bridge Deposit:", bridgeDeposit);
        console2.log("Token:", token);
        console2.log("Amount:", amount);
        console2.log("Destination Chain ID:", destChainId);
        console2.log("Destination Recipient:", destRecipient);
        console2.logBytes32(clientDepositId);
        console2.log("Caller:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        if (clientDepositId == bytes32(0)) {
            depositId = Tip20BridgeDeposit(bridgeDeposit).depositForBridge(token, amount, destChainId, destRecipient);
        } else {
            depositId = Tip20BridgeDeposit(bridgeDeposit)
                .depositForBridgeWithMemo(token, amount, destChainId, destRecipient, clientDepositId);
        }
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("TIP-20 bridge deposit complete. Deposit ID:", depositId);
        console2.log("--------------------------------");
    }
}
