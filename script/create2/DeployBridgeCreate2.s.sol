// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LimitedMinterBridge} from "../../src/LimitedMinterBridge.sol";
import {BridgeDeposit} from "../../src/BridgeDeposit.sol";

/**
 * @title DeployBridgeCreate2
 * @notice Deploys LimitedMinterBridge and BridgeDeposit with deterministic addresses
 *         using Arachnid's CREATE2 proxy (0x4e59b44847b379578588920cA78FbF26c0B4956C).
 * @dev
 *  - Uses CREATE2 to deploy both contracts with the same addresses across all chains.
 *  - Constructor args must be identical across chains for deterministic addresses.
 *  - LimitedMinterBridge is deployed with admin as initial minter; BridgeDeposit gets
 *    MINTER_ROLE granted post-deployment via GrantMinterRole.s.sol.
 *
 * Environment variables:
 *  - BRIDGE_ADMIN: Admin address (must be same on all chains)
 *  - FEE_COLLECTOR: Address that receives bridge fees (must be same on all chains, can be 0x0)
 *  - SALT_LIMITED_MINTER: bytes32 salt for LimitedMinterBridge (optional, default: 0x01)
 *  - SALT_BRIDGE_DEPOSIT: bytes32 salt for BridgeDeposit (optional, default: 0x02)
 */
contract DeployBridgeCreate2 is Script {
    /// @notice Arachnid's Deterministic Deployment Proxy - deployed on most chains
    address constant ARACHNID_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    error ProxyNotDeployed();
    error DeploymentFailed(string contractName);
    error AddressMismatch(string contractName, address expected, address actual);

    function run(address wallet) public returns (address limitedMinter, address bridgeDeposit) {
        // Load environment variables
        address admin = vm.envAddress("BRIDGE_ADMIN");
        address feeCollector = vm.envOr("FEE_COLLECTOR", address(0));
        bytes32 saltLimitedMinter = vm.envOr("SALT_LIMITED_MINTER", bytes32(uint256(1)));
        bytes32 saltBridgeDeposit = vm.envOr("SALT_BRIDGE_DEPOSIT", bytes32(uint256(2)));

        console2.log("================================");
        console2.log("CREATE2 Deployment via Arachnid Proxy");
        console2.log("================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Admin:", admin);
        console2.log("Fee Collector:", feeCollector);
        console2.log("Deployer:", wallet);
        console2.log("Salt (LimitedMinterBridge):", vm.toString(saltLimitedMinter));
        console2.log("Salt (BridgeDeposit):", vm.toString(saltBridgeDeposit));
        console2.log("--------------------------------");

        // Verify Arachnid proxy exists on this chain
        if (ARACHNID_PROXY.code.length == 0) {
            revert ProxyNotDeployed();
        }
        console2.log("Arachnid proxy verified at:", ARACHNID_PROXY);

        // Pre-compute addresses
        (address expectedLimitedMinter, address expectedBridgeDeposit) = computeAddresses(
            admin,
            feeCollector,
            saltLimitedMinter,
            saltBridgeDeposit
        );

        console2.log("Expected LimitedMinterBridge:", expectedLimitedMinter);
        console2.log("Expected BridgeDeposit:", expectedBridgeDeposit);
        console2.log("--------------------------------");

        vm.startBroadcast(wallet);

        // Deploy LimitedMinterBridge
        limitedMinter = deployLimitedMinterBridge(admin, saltLimitedMinter);
        if (limitedMinter != expectedLimitedMinter) {
            revert AddressMismatch("LimitedMinterBridge", expectedLimitedMinter, limitedMinter);
        }

        // Deploy BridgeDeposit
        bridgeDeposit = deployBridgeDeposit(admin, limitedMinter, feeCollector, saltBridgeDeposit);
        if (bridgeDeposit != expectedBridgeDeposit) {
            revert AddressMismatch("BridgeDeposit", expectedBridgeDeposit, bridgeDeposit);
        }

        vm.stopBroadcast();

        console2.log("================================");
        console2.log("Deployment Complete!");
        console2.log("LimitedMinterBridge:", limitedMinter);
        console2.log("BridgeDeposit:", bridgeDeposit);
        console2.log("================================");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. Grant MINTER_ROLE on LimitedMinterBridge to BridgeDeposit:");
        console2.log("   make grant-bridge-minter-role ARGS=\"--network <network>\"");
        console2.log("2. Grant MINTER_ROLE on LatamStable to LimitedMinterBridge");
        console2.log("3. Register token in LimitedMinterBridge");
        console2.log("4. Enable bridge routes in BridgeDeposit");
        console2.log("================================");

        return (limitedMinter, bridgeDeposit);
    }

    function deployLimitedMinterBridge(
        address admin,
        bytes32 salt
    ) internal returns (address deployed) {
        // Construct creation bytecode with constructor args
        // Using admin as initial minter - BridgeDeposit will get MINTER_ROLE post-deployment
        bytes memory creationCode = abi.encodePacked(
            type(LimitedMinterBridge).creationCode,
            abi.encode(admin, admin)
        );

        // Check if already deployed
        deployed = _computeCreate2Addr(salt, keccak256(creationCode));
        if (deployed.code.length > 0) {
            console2.log("LimitedMinterBridge already deployed at:", deployed);
            return deployed;
        }

        // Calldata for Arachnid proxy: salt (32 bytes) + creation code
        bytes memory callData = abi.encodePacked(salt, creationCode);

        // Call the proxy
        (bool success,) = ARACHNID_PROXY.call(callData);

        if (!success) {
            revert DeploymentFailed("LimitedMinterBridge");
        }

        // Verify deployment
        if (deployed.code.length == 0) {
            revert DeploymentFailed("LimitedMinterBridge");
        }

        console2.log("LimitedMinterBridge deployed at:", deployed);
    }

    function deployBridgeDeposit(
        address admin,
        address limitedMinter,
        address feeCollector,
        bytes32 salt
    ) internal returns (address deployed) {
        // Construct creation bytecode with constructor args
        bytes memory creationCode = abi.encodePacked(
            type(BridgeDeposit).creationCode,
            abi.encode(admin, limitedMinter, feeCollector)
        );

        // Check if already deployed
        deployed = _computeCreate2Addr(salt, keccak256(creationCode));
        if (deployed.code.length > 0) {
            console2.log("BridgeDeposit already deployed at:", deployed);
            return deployed;
        }

        // Calldata for Arachnid proxy: salt (32 bytes) + creation code
        bytes memory callData = abi.encodePacked(salt, creationCode);

        // Call the proxy
        (bool success,) = ARACHNID_PROXY.call(callData);

        if (!success) {
            revert DeploymentFailed("BridgeDeposit");
        }

        // Verify deployment
        if (deployed.code.length == 0) {
            revert DeploymentFailed("BridgeDeposit");
        }

        console2.log("BridgeDeposit deployed at:", deployed);
    }

    /**
     * @notice Computes deterministic addresses for both contracts
     * @param admin Admin address (same on all chains)
     * @param feeCollector Fee collector address (same on all chains, can be address(0))
     * @param saltLimitedMinter Salt for LimitedMinterBridge
     * @param saltBridgeDeposit Salt for BridgeDeposit
     * @return limitedMinterAddr Computed LimitedMinterBridge address
     * @return bridgeDepositAddr Computed BridgeDeposit address
     */
    function computeAddresses(
        address admin,
        address feeCollector,
        bytes32 saltLimitedMinter,
        bytes32 saltBridgeDeposit
    ) public pure returns (address limitedMinterAddr, address bridgeDepositAddr) {
        // Compute LimitedMinterBridge address
        bytes memory limitedMinterBytecode = abi.encodePacked(
            type(LimitedMinterBridge).creationCode,
            abi.encode(admin, admin)
        );
        limitedMinterAddr = _computeCreate2Addr(saltLimitedMinter, keccak256(limitedMinterBytecode));

        // Compute BridgeDeposit address using computed LimitedMinterBridge address
        bytes memory bridgeDepositBytecode = abi.encodePacked(
            type(BridgeDeposit).creationCode,
            abi.encode(admin, limitedMinterAddr, feeCollector)
        );
        bridgeDepositAddr = _computeCreate2Addr(saltBridgeDeposit, keccak256(bridgeDepositBytecode));
    }

    /**
     * @notice Computes CREATE2 address using Arachnid proxy
     * @param salt Salt for deployment
     * @param bytecodeHash keccak256 of creation bytecode (including constructor args)
     * @return Computed address
     */
    function _computeCreate2Addr(bytes32 salt, bytes32 bytecodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            ARACHNID_PROXY,
            salt,
            bytecodeHash
        )))));
    }
}
