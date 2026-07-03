// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ITIP20} from "../src/interfaces/ITIP20.sol";

contract GrantTip20Roles is Script {
    function run(address wallet) public {
        address tokenAddress = vm.envAddress("TIP20_TOKEN");
        address issuer = vm.envOr("TIP20_ISSUER", address(0));
        address pauser = vm.envOr("TIP20_PAUSER", address(0));
        address unpauser = vm.envOr("TIP20_UNPAUSER", address(0));
        address burnBlocked = vm.envOr("TIP20_BURN_BLOCKED", address(0));

        ITIP20 token = ITIP20(tokenAddress);

        console2.log("--------------------------------");
        console2.log("Granting TIP-20 roles:");
        console2.log("Token:", tokenAddress);
        console2.log("Caller/Admin:", wallet);
        console2.log("Issuer:", issuer);
        console2.log("Pauser:", pauser);
        console2.log("Unpauser:", unpauser);
        console2.log("Burn blocked:", burnBlocked);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);

        _grantIfSet(token, token.ISSUER_ROLE(), issuer, "ISSUER_ROLE");
        _grantIfSet(token, token.PAUSE_ROLE(), pauser, "PAUSE_ROLE");
        _grantIfSet(token, token.UNPAUSE_ROLE(), unpauser, "UNPAUSE_ROLE");
        _grantIfSet(token, token.BURN_BLOCKED_ROLE(), burnBlocked, "BURN_BLOCKED_ROLE");

        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("TIP-20 role grant script complete");
        console2.log("--------------------------------");
    }

    function _grantIfSet(ITIP20 token, bytes32 role, address account, string memory label) internal {
        if (account == address(0)) {
            console2.log("Skipping unset role:", label);
            return;
        }

        token.grantRole(role, account);
        console2.log("Granted role:", label);
        console2.log("Account:", account);
    }
}
