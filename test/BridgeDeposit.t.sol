// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/BridgeDeposit.sol";
import "../src/LimitedMinterBridge.sol";

contract MockBurnableToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    mapping(address => mapping(bytes32 => bool)) public roles;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public totalSupply;

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return roles[account][role];
    }

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return 0x00;
    }

    function mint(address to, uint256 amount) external {
        require(roles[msg.sender][MINTER_ROLE], "Not minter");
        balances[to] += amount;
        totalSupply += amount;
    }

    function burnFrom(address account, uint256 amount) external {
        require(allowances[account][msg.sender] >= amount, "Insufficient allowance");
        require(balances[account] >= amount, "Insufficient balance");
        allowances[account][msg.sender] -= amount;
        balances[account] -= amount;
        totalSupply -= amount;
    }

    function approve(address spender, uint256 amount) external {
        allowances[msg.sender][spender] = amount;
    }

    function grantRole(bytes32 role, address account) external {
        roles[account][role] = true;
    }
}

contract BridgeDepositTest is Test {
    BridgeDeposit public bridge;
    LimitedMinterBridge public limitedMinter;
    MockBurnableToken public token;

    address public admin = address(0xA);
    address public bridgeOperator = address(0xB);
    address public externalTokenAdmin = address(0xC);
    address public user = address(0xD);
    address public recipient = address(0xE);

    uint256 public constant DAILY_LIMIT = 10000 ether;
    uint256 public constant DEST_CHAIN_ID = 137;

    function setUp() public {
        // Deploy mock token
        token = new MockBurnableToken();

        // Deploy LimitedMinterBridge
        limitedMinter = new LimitedMinterBridge(admin, admin);

        // Deploy BridgeDeposit
        bridge = new BridgeDeposit(admin, ILimitedMinterBridge(address(limitedMinter)));

        // Grant roles
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), externalTokenAdmin);
        token.grantRole(token.MINTER_ROLE(), address(limitedMinter));

        // Register token in LimitedMinterBridge
        vm.prank(externalTokenAdmin);
        limitedMinter.registerToken(address(token), DAILY_LIMIT);

        // Get role hashes before pranking
        bytes32 minterRole = limitedMinter.MINTER_ROLE();
        bytes32 bridgeOperatorRole = bridge.BRIDGE_OPERATOR_ROLE();

        // Grant MINTER_ROLE on LimitedMinterBridge to BridgeDeposit
        vm.prank(admin);
        limitedMinter.grantRole(minterRole, address(bridge));

        // Add supported token to BridgeDeposit
        vm.prank(admin);
        bridge.setSupportedToken(address(token), true);

        // Grant bridge operator role
        vm.prank(admin);
        bridge.grantRole(bridgeOperatorRole, bridgeOperator);

        // Mint some tokens to user for deposit tests
        // We need to use the limitedMinter to mint (since it has MINTER_ROLE on token)
        // First grant this test contract MINTER_ROLE on limitedMinter
        vm.prank(admin);
        limitedMinter.grantRole(minterRole, address(this));
        limitedMinter.mintTo(address(token), user, 10000 ether);

        // Move to next day so that subsequent tests have full daily limit available
        vm.warp(block.timestamp + 1 days);
    }

    // -------------------------------------------------------------------------
    // depositForBridge tests
    // -------------------------------------------------------------------------

    function testDepositForBridge() public {
        uint256 amount = 100 ether;
        bytes32 clientId = keccak256("client-123");

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        vm.expectEmit(true, true, true, true);
        emit BridgeDeposit.BridgeDepositInitiated(
            1, // depositId
            address(token),
            user,
            amount,
            DEST_CHAIN_ID,
            recipient,
            clientId
        );

        uint256 depositId = bridge.depositForBridge(
            address(token),
            amount,
            DEST_CHAIN_ID,
            recipient,
            clientId
        );
        vm.stopPrank();

        assertEq(depositId, 1);
        assertEq(token.balances(user), 10000 ether - amount);
        assertEq(bridge.nextDepositId(), 2);
    }

    function testDepositForBridgeIncrementsId() public {
        uint256 amount = 100 ether;
        bytes32 clientId = bytes32(0);

        vm.startPrank(user);
        token.approve(address(bridge), amount * 3);

        uint256 id1 = bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, clientId);
        uint256 id2 = bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, clientId);
        uint256 id3 = bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, clientId);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(bridge.nextDepositId(), 4);
    }

    function test_RevertWhen_DepositUnsupportedToken() public {
        MockBurnableToken unsupportedToken = new MockBurnableToken();

        vm.prank(user);
        vm.expectRevert(BridgeDeposit.TokenNotSupported.selector);
        bridge.depositForBridge(address(unsupportedToken), 100 ether, DEST_CHAIN_ID, recipient, bytes32(0));
    }

    function test_RevertWhen_DepositZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(BridgeDeposit.AmountZero.selector);
        bridge.depositForBridge(address(token), 0, DEST_CHAIN_ID, recipient, bytes32(0));
    }

    function test_RevertWhen_DepositZeroRecipient() public {
        vm.startPrank(user);
        token.approve(address(bridge), 100 ether);
        vm.expectRevert(BridgeDeposit.InvalidRecipient.selector);
        bridge.depositForBridge(address(token), 100 ether, DEST_CHAIN_ID, address(0), bytes32(0));
        vm.stopPrank();
    }

    function test_RevertWhen_DepositWhilePaused() public {
        vm.prank(admin);
        bridge.pause();

        vm.startPrank(user);
        token.approve(address(bridge), 100 ether);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        bridge.depositForBridge(address(token), 100 ether, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // fulfillBridgeMint tests
    // -------------------------------------------------------------------------

    function testFulfillBridgeMint() public {
        uint256 amount = 500 ether;
        uint256 sourceChainId = 1;
        bytes32 sourceTxHash = keccak256("tx-hash-123");

        vm.prank(bridgeOperator);
        vm.expectEmit(true, true, true, true);
        emit BridgeDeposit.BridgeMintFulfilled(
            address(token),
            recipient,
            amount,
            sourceChainId,
            sourceTxHash
        );
        bridge.fulfillBridgeMint(address(token), recipient, amount, sourceChainId, sourceTxHash);

        assertEq(token.balances(recipient), amount);
        assertTrue(bridge.bridgeFulfilled(sourceTxHash));
    }

    function test_RevertWhen_FulfillByNonOperator() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        vm.prank(user);
        vm.expectRevert();
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash);
    }

    function test_RevertWhen_FulfillAlreadyFulfilled() public {
        bytes32 sourceTxHash = keccak256("tx-hash-duplicate");

        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash);

        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.BridgeAlreadyFulfilled.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash);
    }

    function test_RevertWhen_FulfillUnsupportedToken() public {
        MockBurnableToken unsupportedToken = new MockBurnableToken();
        bytes32 sourceTxHash = keccak256("tx-hash");

        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.TokenNotSupported.selector);
        bridge.fulfillBridgeMint(address(unsupportedToken), recipient, 100 ether, 1, sourceTxHash);
    }

    function test_RevertWhen_FulfillZeroAmount() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.AmountZero.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 0, 1, sourceTxHash);
    }

    function test_RevertWhen_FulfillZeroRecipient() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.InvalidRecipient.selector);
        bridge.fulfillBridgeMint(address(token), address(0), 100 ether, 1, sourceTxHash);
    }

    function test_RevertWhen_FulfillWhilePaused() public {
        vm.prank(admin);
        bridge.pause();

        bytes32 sourceTxHash = keccak256("tx-hash");
        vm.prank(bridgeOperator);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash);
    }

    function testFulfillRespectsLimitedMinterDailyLimit() public {
        // Mint up to the daily limit
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, DAILY_LIMIT, 1, keccak256("tx-1"));

        // Try to mint more - should fail due to daily limit
        vm.prank(bridgeOperator);
        vm.expectRevert(LimitedMinterBridge.ExceedsDailyMintLimit.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 1 ether, 1, keccak256("tx-2"));

        // Next day should work
        vm.warp(block.timestamp + 1 days);
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 1000 ether, 1, keccak256("tx-3"));
    }

    // -------------------------------------------------------------------------
    // Admin function tests
    // -------------------------------------------------------------------------

    function testSetSupportedToken() public {
        MockBurnableToken newToken = new MockBurnableToken();
        newToken.grantRole(newToken.DEFAULT_ADMIN_ROLE(), externalTokenAdmin);
        newToken.grantRole(newToken.MINTER_ROLE(), address(limitedMinter));

        // Register in LimitedMinterBridge first
        vm.prank(externalTokenAdmin);
        limitedMinter.registerToken(address(newToken), 1000 ether);

        // Now add to BridgeDeposit
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit BridgeDeposit.SupportedTokenUpdated(address(newToken), true);
        bridge.setSupportedToken(address(newToken), true);

        assertTrue(bridge.supportedTokens(address(newToken)));
    }

    function test_RevertWhen_SetSupportedTokenNotInMinter() public {
        MockBurnableToken newToken = new MockBurnableToken();

        vm.prank(admin);
        vm.expectRevert(BridgeDeposit.TokenNotRegisteredInMinter.selector);
        bridge.setSupportedToken(address(newToken), true);
    }

    function testRemoveSupportedToken() public {
        vm.prank(admin);
        bridge.setSupportedToken(address(token), false);

        assertFalse(bridge.supportedTokens(address(token)));
    }

    function testUpdateLimitedMinter() public {
        LimitedMinterBridge newMinter = new LimitedMinterBridge(admin, admin);

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit BridgeDeposit.LimitedMinterUpdated(address(limitedMinter), address(newMinter));
        bridge.updateLimitedMinter(ILimitedMinterBridge(address(newMinter)));

        assertEq(address(bridge.limitedMinter()), address(newMinter));
    }

    function test_RevertWhen_UpdateLimitedMinterZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(BridgeDeposit.ZeroAddress.selector);
        bridge.updateLimitedMinter(ILimitedMinterBridge(address(0)));
    }

    function testPauseAndUnpause() public {
        vm.prank(admin);
        bridge.pause();
        assertTrue(bridge.paused());

        vm.prank(admin);
        bridge.unpause();
        assertFalse(bridge.paused());
    }

    // -------------------------------------------------------------------------
    // View function tests
    // -------------------------------------------------------------------------

    function testRemainingMintCapacity() public {
        // Initially full capacity
        (uint256 remaining, uint256 dailyMax, uint256 mintedToday) = bridge.remainingMintCapacity(address(token));
        assertEq(remaining, DAILY_LIMIT);
        assertEq(dailyMax, DAILY_LIMIT);
        assertEq(mintedToday, 0);

        // After minting some
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 3000 ether, 1, keccak256("tx-1"));

        (remaining, dailyMax, mintedToday) = bridge.remainingMintCapacity(address(token));
        assertEq(remaining, DAILY_LIMIT - 3000 ether);
        assertEq(dailyMax, DAILY_LIMIT);
        assertEq(mintedToday, 3000 ether);
    }

    function testRemainingMintCapacityAfterDayReset() public {
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, DAILY_LIMIT, 1, keccak256("tx-1"));

        (uint256 remaining,,) = bridge.remainingMintCapacity(address(token));
        assertEq(remaining, 0);

        // Next day
        vm.warp(block.timestamp + 1 days);
        (remaining,,) = bridge.remainingMintCapacity(address(token));
        assertEq(remaining, DAILY_LIMIT);
    }
}
