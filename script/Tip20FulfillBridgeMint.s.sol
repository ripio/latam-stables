// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Tip20BridgeDeposit} from "../src/Tip20BridgeDeposit.sol";

contract Tip20FulfillBridgeMint is Script {
    function run(address wallet) public {
        address bridgeDeposit = vm.envAddress("TIP20_BRIDGE_DEPOSIT");
        address token = vm.envAddress("TIP20_TOKEN");
        address to = vm.envAddress("BRIDGE_RECIPIENT");
        uint256 amount = vm.envUint("BRIDGE_AMOUNT");
        uint256 sourceChainId = vm.envUint("SOURCE_CHAIN_ID");
        bytes32 sourceTxHash = vm.envBytes32("SOURCE_TX_HASH");
        uint256 sourceDepositId = vm.envUint("SOURCE_DEPOSIT_ID");
        bytes32 memo = vm.envOr("BRIDGE_MEMO", bytes32(0));

        console2.log("--------------------------------");
        console2.log("Fulfilling TIP-20 bridge mint:");
        console2.log("Bridge Deposit:", bridgeDeposit);
        console2.log("Token:", token);
        console2.log("Recipient:", to);
        console2.log("Amount:", amount);
        console2.log("Source Chain ID:", sourceChainId);
        console2.logBytes32(sourceTxHash);
        console2.log("Source Deposit ID:", sourceDepositId);
        console2.logBytes32(memo);
        console2.log("Caller:", wallet);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);
        if (memo == bytes32(0)) {
            Tip20BridgeDeposit(bridgeDeposit)
                .fulfillBridgeMint(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId);
        } else {
            Tip20BridgeDeposit(bridgeDeposit)
                .fulfillBridgeMintWithMemo(token, to, amount, sourceChainId, sourceTxHash, sourceDepositId, memo);
        }
        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("TIP-20 bridge mint fulfilled");
        console2.log("--------------------------------");
    }
}
