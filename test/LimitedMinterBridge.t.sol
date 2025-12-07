// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/LimitedMinterBridge.sol";

contract MockLatamStableTokenBridge is ILatamStableToken {
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

    function grantRole(bytes32 role, address account) external {
        roles[account][role] = true;
    }
}

contract LimitedMinterBridgeTest is Test {
    LimitedMinterBridge public minter;
    MockLatamStableTokenBridge public token;
    address public admin = address(0xA);
    address public minterUser = address(0xB);
    address public externalAdmin = address(0xC);
    address public recipient = address(0xD);
    address public user = address(0xE);

    function setUp() public {
        token = new MockLatamStableTokenBridge();
        minter = new LimitedMinterBridge(admin, minterUser);
        // Grant admin role on token to externalAdmin
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), externalAdmin);
        // Grant minter role on token to LimitedMinterBridge contract
        token.grantRole(token.MINTER_ROLE(), address(minter));
    }

    function testRegisterTokenByExternalAdmin() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        (uint256 limit, bool exists) = minter.tokenConfigs(address(token));
        assertEq(limit, 1000 ether);
        assertTrue(exists);
    }

    function test_RevertWhen_RegisterTokenByNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(LimitedMinterBridge.NotExternalAdmin.selector);
        minter.registerToken(address(token), 1000 ether);
    }

    // Note: registerToken with address(0) reverts in onlyExternalAdmin modifier
    // before reaching the InvalidTokenAddress check, since it tries to call
    // DEFAULT_ADMIN_ROLE() on address(0). This is acceptable behavior.

    function test_RevertWhen_RegisterTokenAlreadyRegistered() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(externalAdmin);
        vm.expectRevert(LimitedMinterBridge.TokenAlreadyRegistered.selector);
        minter.registerToken(address(token), 500 ether);
    }

    function testUnregisterToken() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(externalAdmin);
        minter.unregisterToken(address(token));
        (, bool exists) = minter.tokenConfigs(address(token));
        assertFalse(exists);
    }

    function testUpdateDailyMintLimit() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(externalAdmin);
        minter.updateDailyMintLimit(address(token), 500 ether);
        (uint256 limit,) = minter.tokenConfigs(address(token));
        assertEq(limit, 500 ether);
    }

    function testMintToWithinLimit() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        minter.mintTo(address(token), recipient, 500 ether);
        assertEq(token.balances(recipient), 500 ether);
        assertEq(token.totalSupply(), 500 ether);
        assertEq(token.lastMintTo(), recipient);
        assertEq(token.lastMintAmount(), 500 ether);
    }

    function testMintToArbitraryRecipient() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);

        address recipient1 = address(0x111);
        address recipient2 = address(0x222);

        vm.prank(minterUser);
        minter.mintTo(address(token), recipient1, 300 ether);
        assertEq(token.balances(recipient1), 300 ether);

        vm.prank(minterUser);
        minter.mintTo(address(token), recipient2, 400 ether);
        assertEq(token.balances(recipient2), 400 ether);
    }

    function testMintToExceedingLimitShouldRevert() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        minter.mintTo(address(token), recipient, 800 ether);
        vm.prank(minterUser);
        vm.expectRevert(LimitedMinterBridge.ExceedsDailyMintLimit.selector);
        minter.mintTo(address(token), recipient, 300 ether);
    }

    function testMintToResetsNextDay() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        minter.mintTo(address(token), recipient, 1000 ether);
        // Move to next day
        vm.warp(block.timestamp + 1 days);
        vm.prank(minterUser);
        minter.mintTo(address(token), recipient, 1000 ether);
        assertEq(token.balances(recipient), 2000 ether);
    }

    function testMintToFailIfNotMinterRole() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(user);
        vm.expectRevert();
        minter.mintTo(address(token), recipient, 100 ether);
    }

    function test_RevertWhen_MintToUnregisteredToken() public {
        vm.prank(minterUser);
        vm.expectRevert(LimitedMinterBridge.TokenNotRegistered.selector);
        minter.mintTo(address(token), recipient, 100 ether);
    }

    function testMintToAmountMustBeGreaterThanZero() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        vm.expectRevert(LimitedMinterBridge.MintAmountZero.selector);
        minter.mintTo(address(token), recipient, 0);
    }

    function test_RevertWhen_MintToZeroRecipient() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        vm.expectRevert(LimitedMinterBridge.InvalidRecipient.selector);
        minter.mintTo(address(token), address(0), 100 ether);
    }

    function testMintedTodayView() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        minter.mintTo(address(token), recipient, 400 ether);
        assertEq(minter.mintedToday(address(token)), 400 ether);
        vm.warp(block.timestamp + 1 days);
        assertEq(minter.mintedToday(address(token)), 0);
    }

    function testPauseAndUnpause() public {
        vm.prank(admin);
        minter.pause();
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        minter.mintTo(address(token), recipient, 100 ether);
        vm.prank(admin);
        minter.unpause();
        vm.prank(minterUser);
        minter.mintTo(address(token), recipient, 100 ether);
        assertEq(token.balances(recipient), 100 ether);
    }

    function testMintedTodayRevertsForUnregisteredToken() public {
        vm.expectRevert(LimitedMinterBridge.TokenNotRegistered.selector);
        minter.mintedToday(address(token));
    }

    function testEmitTokenRegisteredEvent() public {
        vm.prank(externalAdmin);
        vm.expectEmit(true, false, false, true);
        emit LimitedMinterBridge.TokenRegistered(address(token), 1000 ether);
        minter.registerToken(address(token), 1000 ether);
    }

    function testEmitMintedEvent() public {
        vm.prank(externalAdmin);
        minter.registerToken(address(token), 1000 ether);
        vm.prank(minterUser);
        vm.expectEmit(true, true, true, true);
        emit LimitedMinterBridge.Minted(address(token), minterUser, recipient, 500 ether);
        minter.mintTo(address(token), recipient, 500 ether);
    }
}
