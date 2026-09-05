// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {VerifyDeployment} from "../script/create2/VerifyDeployment.s.sol";
import {LimitedMinterBridge} from "../src/LimitedMinterBridge.sol";
import {BridgeDeposit, ILimitedMinterBridge} from "../src/BridgeDeposit.sol";

contract VerifyDeploymentHarness is VerifyDeployment {
    function verify(address minter, address bridge) external view {
        _verifyDeployment(minter, bridge);
    }
}

contract VerifyDeploymentTest is Test {
    VerifyDeploymentHarness internal verifier;
    address internal admin = address(0xA11CE);

    function setUp() public {
        verifier = new VerifyDeploymentHarness();
    }

    function test_RevertWhen_ContractsAreMissing() public {
        vm.expectRevert(VerifyDeployment.DeploymentVerificationFailed.selector);
        verifier.verify(address(0x1111), address(0x2222));
    }

    function test_RevertWhen_BridgeLacksMinterRole() public {
        LimitedMinterBridge minter = new LimitedMinterBridge(admin, admin);
        BridgeDeposit bridge = new BridgeDeposit(admin, ILimitedMinterBridge(address(minter)), address(0));
        vm.expectRevert(VerifyDeployment.DeploymentVerificationFailed.selector);
        verifier.verify(address(minter), address(bridge));
    }

    function test_RevertWhen_BridgeLinksWrongMinter() public {
        LimitedMinterBridge expectedMinter = new LimitedMinterBridge(admin, admin);
        LimitedMinterBridge actualMinter = new LimitedMinterBridge(admin, admin);
        BridgeDeposit bridge = new BridgeDeposit(admin, ILimitedMinterBridge(address(actualMinter)), address(0));

        bytes32 minterRole = expectedMinter.MINTER_ROLE();
        vm.prank(admin);
        expectedMinter.grantRole(minterRole, address(bridge));

        vm.expectRevert(VerifyDeployment.DeploymentVerificationFailed.selector);
        verifier.verify(address(expectedMinter), address(bridge));
    }

    function test_CompletesWhen_AllChecksPass() public {
        LimitedMinterBridge minter = new LimitedMinterBridge(admin, admin);
        BridgeDeposit bridge = new BridgeDeposit(admin, ILimitedMinterBridge(address(minter)), address(0));

        bytes32 minterRole = minter.MINTER_ROLE();
        vm.prank(admin);
        minter.grantRole(minterRole, address(bridge));
        verifier.verify(address(minter), address(bridge));
    }
}
