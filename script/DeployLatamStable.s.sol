// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LatamStable} from "../src/LatamStable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployLatamStable is Script {
    function run(address wallet) public returns (address)  {
        address deployer = wallet;

        // Define initialization parameters
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
        address pauser = vm.envAddress("PAUSER");
        address minter = vm.envAddress("MINTER");
        address upgrader = vm.envAddress("UPGRADER");
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");

        // Log parameter values
        console2.log("--------------------------------");
        console2.log("Deploying LatamStable with the following parameters:");
        console2.log("Default Admin:", defaultAdmin);
        console2.log("Pauser:", pauser);
        console2.log("Minter:", minter);
        console2.log("Upgrader:", upgrader);
        console2.log("Token Name:", tokenName);
        console2.log("Token Symbol:", tokenSymbol);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);

        // Deploy the contract implementation
        LatamStable implementation = new LatamStable();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            LatamStable.initialize.selector,
            defaultAdmin,
            pauser,
            minter,
            upgrader,
            tokenName,
            tokenSymbol
        );

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        address latamStableAddress = address(proxy);

        vm.stopBroadcast();

        console2.log("--------------------------------");
        console2.log("LatamStable deployed at:", latamStableAddress);
        console2.log("Implementation deployed at:", address(implementation));
        console2.log("Deployer:", deployer);
        console2.log("Token Name:", tokenName);
        console2.log("Token Symbol:", tokenSymbol); 
        console2.log("Default Admin:", defaultAdmin);
        console2.log("Pauser:", pauser);
        console2.log("Minter:", minter);
        console2.log("Upgrader:", upgrader);
        console2.log("Contract initialized successfully");
        console2.log("--------------------------------");
        return latamStableAddress;
    }
} 