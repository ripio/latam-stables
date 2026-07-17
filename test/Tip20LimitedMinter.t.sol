// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Tip20LimitedMinter} from "../src/Tip20LimitedMinter.sol";

/// @dev Minimal TIP-20 mock modelling the mint entrypoints used by Tip20LimitedMinter.
///      `redirectMints` simulates a transfer-policy that swallows the mint (no balance change)
///      to exercise the `UnexpectedTokenDelivery` guard. `lastMemo`/`lastMintTo` let tests
///      assert that the exact memo and destination reach the token.
contract MockTip20 {
    string public name = "Mock TIP-20";
    string public symbol = "MTIP";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    bool public redirectMints;

    bytes32 public lastMemo;
    address public lastMintTo;
    uint256 public lastMintAmount;
    bool public lastMintUsedMemo;

    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TransferWithMemo(address indexed from, address indexed to, uint256 amount, bytes32 indexed memo);

    function mintForTest(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function mint(address to, uint256 amount) external {
        lastMintTo = to;
        lastMintAmount = amount;
        lastMemo = bytes32(0);
        lastMintUsedMemo = false;
        if (!redirectMints) {
            balanceOf[to] += amount;
            totalSupply += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function mintWithMemo(address to, uint256 amount, bytes32 memo) external {
        lastMintTo = to;
        lastMintAmount = amount;
        lastMemo = memo;
        lastMintUsedMemo = true;
        if (!redirectMints) {
            balanceOf[to] += amount;
            totalSupply += amount;
        }
        emit TransferWithMemo(address(0), to, amount, memo);
    }

    function setRedirectMints(bool enabled) external {
        redirectMints = enabled;
    }
}

contract Tip20LimitedMinterTest is Test {
    // Mirrors Tip20LimitedMinter.Minted for vm.expectEmit
    event Minted(
        address indexed token, address indexed minter, address indexed destination, uint256 amount, bytes32 memo
    );

    address internal admin = address(0xA11CE);
    address internal minter = address(0xB0B);
    address internal configAdmin = address(0xC04F16);
    address internal destination = address(0xD00D);
    address internal stranger = address(0xBAD);

    uint256 internal constant DAILY_CAP = 1_000_000; // 1 token at 6 decimals
    uint256 internal constant BASE_TS = 1_700_000_000;
    bytes32 internal memo = bytes32(uint256(0xABCD));

    MockTip20 internal token;
    Tip20LimitedMinter internal limitedMinter;

    // Cached in setUp so reading them never consumes a vm.prank during expectRevert arg evaluation.
    bytes32 internal MINTER_ROLE;
    bytes32 internal TOKEN_CONFIG_ADMIN_ROLE;
    bytes32 internal DEFAULT_ADMIN_ROLE;

    function setUp() public {
        vm.warp(BASE_TS);

        token = new MockTip20();
        limitedMinter = new Tip20LimitedMinter(admin, minter, configAdmin);

        MINTER_ROLE = limitedMinter.MINTER_ROLE();
        TOKEN_CONFIG_ADMIN_ROLE = limitedMinter.TOKEN_CONFIG_ADMIN_ROLE();
        DEFAULT_ADMIN_ROLE = limitedMinter.DEFAULT_ADMIN_ROLE();

        vm.prank(configAdmin);
        limitedMinter.registerToken(address(token), destination, DAILY_CAP);
    }

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    function testConstructorRevertsOnZeroDefaultAdmin() public {
        vm.expectRevert(Tip20LimitedMinter.ZeroAddress.selector);
        new Tip20LimitedMinter(address(0), minter, configAdmin);
    }

    function testConstructorRevertsOnZeroMinter() public {
        vm.expectRevert(Tip20LimitedMinter.ZeroAddress.selector);
        new Tip20LimitedMinter(admin, address(0), configAdmin);
    }

    function testConstructorRevertsOnZeroConfigAdmin() public {
        vm.expectRevert(Tip20LimitedMinter.ZeroAddress.selector);
        new Tip20LimitedMinter(admin, minter, address(0));
    }

    // ---------------------------------------------------------------------
    // Happy paths
    // ---------------------------------------------------------------------

    function testMintCreditsDestinationAndTracksDay() public {
        vm.prank(minter);
        limitedMinter.mint(address(token), 400_000);

        assertEq(token.balanceOf(destination), 400_000);
        assertEq(token.lastMintTo(), destination);
        assertEq(token.lastMintUsedMemo(), false);
        assertEq(limitedMinter.mintedToday(address(token)), 400_000);
    }

    function testMintWithMemoPropagatesMemo() public {
        vm.prank(minter);
        limitedMinter.mintWithMemo(address(token), 500_000, memo);

        assertEq(token.balanceOf(destination), 500_000);
        assertEq(token.lastMintUsedMemo(), true);
        assertEq(token.lastMemo(), memo);
        assertEq(limitedMinter.mintedToday(address(token)), 500_000);
    }

    function testMintEmitsMintedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Minted(address(token), minter, destination, 300_000, bytes32(0));

        vm.prank(minter);
        limitedMinter.mint(address(token), 300_000);
    }

    // ---------------------------------------------------------------------
    // Cap enforcement & day rollover
    // ---------------------------------------------------------------------

    function testMintUpToCapThenReverts() public {
        vm.prank(minter);
        limitedMinter.mint(address(token), DAILY_CAP);
        assertEq(limitedMinter.mintedToday(address(token)), DAILY_CAP);

        vm.prank(minter);
        vm.expectRevert(Tip20LimitedMinter.ExceedsDailyMintLimit.selector);
        limitedMinter.mint(address(token), 1);
    }

    function testCapResetsNextDay() public {
        vm.prank(minter);
        limitedMinter.mint(address(token), DAILY_CAP);

        vm.warp(BASE_TS + 1 days);
        assertEq(limitedMinter.mintedToday(address(token)), 0);

        vm.prank(minter);
        limitedMinter.mint(address(token), DAILY_CAP);

        assertEq(token.balanceOf(destination), 2 * DAILY_CAP);
        assertEq(limitedMinter.mintedToday(address(token)), DAILY_CAP);
    }

    // ---------------------------------------------------------------------
    // Access control
    // ---------------------------------------------------------------------

    function testMintRevertsForNonMinter() public {
        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, MINTER_ROLE));
        limitedMinter.mint(address(token), 1);
    }

    function testRegisterRevertsForNonConfigAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, TOKEN_CONFIG_ADMIN_ROLE));
        limitedMinter.registerToken(address(0x1234), destination, DAILY_CAP);
    }

    function testUpdateDailyLimitRevertsForNonConfigAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, TOKEN_CONFIG_ADMIN_ROLE));
        limitedMinter.updateDailyMintLimit(address(token), 1);
    }

    function testUpdateMintDestinationRevertsForNonConfigAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, TOKEN_CONFIG_ADMIN_ROLE));
        limitedMinter.updateMintDestination(address(token), stranger);
    }

    function testUnregisterRevertsForNonConfigAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, TOKEN_CONFIG_ADMIN_ROLE));
        limitedMinter.unregisterToken(address(token));
    }

    function testPauseRevertsForNonAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, DEFAULT_ADMIN_ROLE));
        limitedMinter.pause();
    }

    // ---------------------------------------------------------------------
    // Pause
    // ---------------------------------------------------------------------

    function testPauseBlocksMintingThenUnpauseRestores() public {
        vm.prank(admin);
        limitedMinter.pause();

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        limitedMinter.mint(address(token), 1);

        vm.prank(admin);
        limitedMinter.unpause();

        vm.prank(minter);
        limitedMinter.mint(address(token), 100_000);
        assertEq(token.balanceOf(destination), 100_000);
    }

    // ---------------------------------------------------------------------
    // Input validation
    // ---------------------------------------------------------------------

    function testMintZeroAmountReverts() public {
        vm.prank(minter);
        vm.expectRevert(Tip20LimitedMinter.MintAmountZero.selector);
        limitedMinter.mint(address(token), 0);
    }

    function testMintUnregisteredTokenReverts() public {
        vm.prank(minter);
        vm.expectRevert(Tip20LimitedMinter.TokenNotRegistered.selector);
        limitedMinter.mint(address(0xDEAD), 1);
    }

    function testMintedTodayRevertsForUnregisteredToken() public {
        vm.expectRevert(Tip20LimitedMinter.TokenNotRegistered.selector);
        limitedMinter.mintedToday(address(0xDEAD));
    }

    function testRegisterZeroTokenReverts() public {
        vm.prank(configAdmin);
        vm.expectRevert(Tip20LimitedMinter.InvalidTokenAddress.selector);
        limitedMinter.registerToken(address(0), destination, DAILY_CAP);
    }

    function testRegisterZeroDestinationReverts() public {
        vm.prank(configAdmin);
        vm.expectRevert(Tip20LimitedMinter.InvalidMintDestination.selector);
        limitedMinter.registerToken(address(0x1234), address(0), DAILY_CAP);
    }

    function testRegisterAlreadyRegisteredReverts() public {
        vm.prank(configAdmin);
        vm.expectRevert(Tip20LimitedMinter.TokenAlreadyRegistered.selector);
        limitedMinter.registerToken(address(token), destination, DAILY_CAP);
    }

    // ---------------------------------------------------------------------
    // Config updates
    // ---------------------------------------------------------------------

    function testUpdateMintDestinationRedirectsMints() public {
        address newDestination = address(0xBEEF);
        vm.prank(configAdmin);
        limitedMinter.updateMintDestination(address(token), newDestination);

        vm.prank(minter);
        limitedMinter.mint(address(token), 200_000);

        assertEq(token.balanceOf(newDestination), 200_000);
        assertEq(token.balanceOf(destination), 0);
    }

    function testUpdateMintDestinationZeroReverts() public {
        vm.prank(configAdmin);
        vm.expectRevert(Tip20LimitedMinter.InvalidMintDestination.selector);
        limitedMinter.updateMintDestination(address(token), address(0));
    }

    function testUpdateDailyLimitIsEnforced() public {
        vm.prank(configAdmin);
        limitedMinter.updateDailyMintLimit(address(token), 100_000);

        vm.prank(minter);
        vm.expectRevert(Tip20LimitedMinter.ExceedsDailyMintLimit.selector);
        limitedMinter.mint(address(token), 100_001);

        vm.prank(minter);
        limitedMinter.mint(address(token), 100_000);
        assertEq(token.balanceOf(destination), 100_000);
    }

    // ---------------------------------------------------------------------
    // UnexpectedTokenDelivery guard
    // ---------------------------------------------------------------------

    function testMintRevertsWhenDeliveryRedirected() public {
        token.setRedirectMints(true);

        vm.prank(minter);
        vm.expectRevert(Tip20LimitedMinter.UnexpectedTokenDelivery.selector);
        limitedMinter.mint(address(token), 100_000);
    }

    // ---------------------------------------------------------------------
    // mintedPerDay persistence across unregister / re-register (anti cap-reset)
    // ---------------------------------------------------------------------

    function testMintedPerDayPersistsAcrossReRegister() public {
        vm.prank(minter);
        limitedMinter.mint(address(token), 600_000);
        assertEq(limitedMinter.mintedToday(address(token)), 600_000);

        vm.startPrank(configAdmin);
        limitedMinter.unregisterToken(address(token));
        limitedMinter.registerToken(address(token), destination, DAILY_CAP);
        vm.stopPrank();

        // Same UTC day: the accumulated 600_000 is retained, so only 400_000 remains mintable.
        assertEq(limitedMinter.mintedToday(address(token)), 600_000);

        vm.prank(minter);
        vm.expectRevert(Tip20LimitedMinter.ExceedsDailyMintLimit.selector);
        limitedMinter.mint(address(token), 400_001);

        vm.prank(minter);
        limitedMinter.mint(address(token), 400_000);
        assertEq(limitedMinter.mintedToday(address(token)), DAILY_CAP);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _unauthorized(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", account, role);
    }
}
