// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/LimitedMinter.sol";

contract MockLatamStableToken is ILatamStableToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    mapping(address => mapping(bytes32 => bool)) public roles;
    mapping(address => uint256) public balances;
    uint256 public totalSupply;
    address public lastMintTo;
    uint256 public lastMintAmount;

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return roles[account][role];
    }
    function DEFAULT_ADMIN_ROLE() external pure override returns (bytes32) {
        return 0x00;
    }
    function mint(address to, uint256 amount) external override {
        require(roles[msg.sender][MINTER_ROLE], "Not minter");
        balances[to] += amount;
        totalSupply += amount;
        lastMintTo = to;
        lastMintAmount = amount;
    }
    // Helper for tests
    function grantRole(bytes32 role, address account) external {
        roles[account][role] = true;
    }
}

contract LimitedMinterTest is Test {
    LimitedMinter public minter;
    MockLatamStableToken public token;
    address public admin = address(0xA);
    address public minterUser = address(0xB);
    address public externalAdmin = address(0xC);
    address public destination = address(0xD);
    address public user = address(0xE);

    function setUp() public {
        token = new MockLatamStableToken();
        minter = new LimitedMinter(admin, minterUser);
        // Grant admin role on token to externalAdmin
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), externalAdmin);
        // Grant minter role on token to LimitedMinter contract
        token.grantRole(token.MINTER_ROLE(), address(minter));
    }

    function testRegisterTokenByExternalAdmin() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        (address dest, uint256 limit, bool exists) = minter.tokenConfigs(address(token));
        assertEq(dest, destination);
        assertEq(limit, 1000 ether);
        assertTrue(exists);
    }

    function test_RevertWhen_RegisterTokenByNonAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        minter.registerToken(address(token), destination, 1000 ether);
    }

    function testUnregisterToken() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(externalAdmin);
        minter.unregisterToken(address(token));
        (,, bool exists) = minter.tokenConfigs(address(token));
        assertFalse(exists);
    }

    function testUpdateDailyMintLimit() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(externalAdmin);
        minter.updateDailyMintLimit(address(token), 500 ether);
        (, uint256 limit, ) = minter.tokenConfigs(address(token));
        assertEq(limit, 500 ether);
    }

    function testUpdateMintDestination() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        address newDest = address(0xF);
        vm.prank(externalAdmin);
        minter.updateMintDestination(address(token), newDest);
        (address dest,, ) = minter.tokenConfigs(address(token));
        assertEq(dest, newDest);
    }

    function testMintWithinLimit() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(minterUser);
        minter.mint(address(token), 500 ether);
        assertEq(token.balances(destination), 500 ether);
        assertEq(token.totalSupply(), 500 ether);
    }

    function testMintExceedingLimitShouldRevert() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(minterUser);
        minter.mint(address(token), 800 ether);
        vm.prank(minterUser);
        vm.expectRevert(LimitedMinter.ExceedsDailyMintLimit.selector);
        minter.mint(address(token), 300 ether);
    }

    function testMintResetsNextDay() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(minterUser);
        minter.mint(address(token), 1000 ether);
        // Move to next day
        vm.warp(block.timestamp + 1 days);
        vm.prank(minterUser);
        minter.mint(address(token), 1000 ether);
        assertEq(token.balances(destination), 2000 ether);
    }

    function testMintFailIfNotMinterRole() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(user);
        vm.expectRevert();
        minter.mint(address(token), 100 ether);
    }

    function test_RevertWhen_MintUnregisteredToken() public {
        vm.prank(minterUser);
        vm.expectRevert();
        minter.mint(address(token), 100 ether);
    }

    function testMintAmountMustBeGreaterThanZero() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(minterUser);
        vm.expectRevert(LimitedMinter.MintAmountZero.selector);
        minter.mint(address(token), 0);
    }

    function testMintedTodayView() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(minterUser);
        minter.mint(address(token), 400 ether);
        assertEq(minter.mintedToday(address(token)), 400 ether);
        vm.warp(block.timestamp + 1 days);
        assertEq(minter.mintedToday(address(token)), 0);
    }

    function testPauseAndUnpause() public {
        vm.prank(admin);
        minter.pause();
        vm.prank(externalAdmin);
        minter.registerToken(address(token), destination, 1000 ether);
        vm.prank(minterUser);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        minter.mint(address(token), 100 ether);
        vm.prank(admin);
        minter.unpause();
        vm.prank(minterUser);
        minter.mint(address(token), 100 ether);
        assertEq(token.balances(destination), 100 ether);
    }

    function testMintedTodayRevertsForUnregisteredToken() public {
        vm.expectRevert(LimitedMinter.TokenNotRegistered.selector);
        minter.mintedToday(address(token));
    }
} 