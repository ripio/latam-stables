// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LimitedMinterBridge} from "../../src/LimitedMinterBridge.sol";
import {BridgeDeposit, ILimitedMinterBridge} from "../../src/BridgeDeposit.sol";

/**
 * @title ComputeAddresses
 * @notice Computes deterministic addresses for LimitedMinterBridge and BridgeDeposit
 *         without deploying. Use this to verify addresses before deployment.
 * @dev
 *  - Run this on any chain to compute addresses (no transaction needed).
 *  - Addresses will be the same on all chains if using the same admin and salts.
 *
 * Environment variables:
 *  - BRIDGE_ADMIN: Admin address (must be same on all chains)
 *  - SALT_LIMITED_MINTER: bytes32 salt for LimitedMinterBridge (optional, default: 0x01)
 *  - SALT_BRIDGE_DEPOSIT: bytes32 salt for BridgeDeposit (optional, default: 0x02)
 */
contract ComputeAddresses is Script {
    /// @notice Arachnid's Deterministic Deployment Proxy
    address constant ARACHNID_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public view {
        // Load environment variables
        address admin = vm.envAddress("BRIDGE_ADMIN");
        bytes32 saltLimitedMinter = vm.envOr("SALT_LIMITED_MINTER", bytes32(uint256(1)));
        bytes32 saltBridgeDeposit = vm.envOr("SALT_BRIDGE_DEPOSIT", bytes32(uint256(2)));

        // Compute LimitedMinterBridge address
        // Constructor: (address defaultAdmin, address minter)
        // Using admin as initial minter (will grant MINTER_ROLE to BridgeDeposit post-deployment)
        bytes memory limitedMinterBytecode = abi.encodePacked(
            type(LimitedMinterBridge).creationCode,
            abi.encode(admin, admin)
        );

        address limitedMinterAddress = _computeCreate2Addr(
            saltLimitedMinter,
            keccak256(limitedMinterBytecode)
        );

        // Compute BridgeDeposit address using computed LimitedMinterBridge address
        // Constructor: (address admin, ILimitedMinterBridge _limitedMinter)
        bytes memory bridgeDepositBytecode = abi.encodePacked(
            type(BridgeDeposit).creationCode,
            abi.encode(admin, limitedMinterAddress)
        );

        address bridgeDepositAddress = _computeCreate2Addr(
            saltBridgeDeposit,
            keccak256(bridgeDepositBytecode)
        );

        // Output results
        console2.log("================================");
        console2.log("CREATE2 Address Computation");
        console2.log("================================");
        console2.log("Factory:", ARACHNID_PROXY);
        console2.log("Admin:", admin);
        console2.log("Salt (LimitedMinterBridge):", vm.toString(saltLimitedMinter));
        console2.log("Salt (BridgeDeposit):", vm.toString(saltBridgeDeposit));
        console2.log("--------------------------------");
        console2.log("LimitedMinterBridge will deploy at:", limitedMinterAddress);
        console2.log("BridgeDeposit will deploy at:", bridgeDepositAddress);
        console2.log("================================");
        console2.log("");
        console2.log("These addresses will be the same on all chains if using");
        console2.log("the same admin address and salt values.");
        console2.log("================================");
    }

    function _computeCreate2Addr(bytes32 salt, bytes32 bytecodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            ARACHNID_PROXY,
            salt,
            bytecodeHash
        )))));
    }
}
