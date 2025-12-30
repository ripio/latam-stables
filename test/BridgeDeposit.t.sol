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

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        require(balances[from] >= amount, "Insufficient balance");
        allowances[from][msg.sender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }

    function grantRole(bytes32 role, address account) external {
        roles[account][role] = true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
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
    address public feeCollector = address(0xF);
    address public feeManager = address(0x1A);

    uint256 public constant DAILY_LIMIT = 10000 ether;
    uint256 public constant DEST_CHAIN_ID = 137;
    uint256 public constant DEFAULT_FEE = 1 ether;

    function setUp() public {
        // Deploy mock token
        token = new MockBurnableToken();

        // Deploy LimitedMinterBridge
        limitedMinter = new LimitedMinterBridge(admin, admin);

        // Deploy BridgeDeposit with feeCollector
        bridge = new BridgeDeposit(admin, ILimitedMinterBridge(address(limitedMinter)), feeCollector);

        // Grant roles
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), externalTokenAdmin);
        token.grantRole(token.MINTER_ROLE(), address(limitedMinter));

        // Register token in LimitedMinterBridge
        vm.prank(externalTokenAdmin);
        limitedMinter.registerToken(address(token), DAILY_LIMIT);

        // Get role hashes before pranking
        bytes32 minterRole = limitedMinter.MINTER_ROLE();
        bytes32 bridgeOperatorRole = bridge.BRIDGE_OPERATOR_ROLE();
        bytes32 feeManagerRole = bridge.FEE_MANAGER_ROLE();

        // Grant MINTER_ROLE on LimitedMinterBridge to BridgeDeposit
        vm.prank(admin);
        limitedMinter.grantRole(minterRole, address(bridge));

        // Add outbound bridge route for token to DEST_CHAIN_ID with no fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, true, 0);

        // Grant bridge operator role
        vm.prank(admin);
        bridge.grantRole(bridgeOperatorRole, bridgeOperator);

        // Grant fee manager role
        vm.prank(admin);
        bridge.grantRole(feeManagerRole, feeManager);

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
            amount, // amountToBurn (no fee)
            0, // fee
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

    function test_RevertWhen_DepositUnsupportedRoute() public {
        MockBurnableToken unsupportedToken = new MockBurnableToken();

        vm.prank(user);
        vm.expectRevert(BridgeDeposit.InvalidRoute.selector);
        bridge.depositForBridge(address(unsupportedToken), 100 ether, DEST_CHAIN_ID, recipient, bytes32(0));
    }

    function test_RevertWhen_DepositToUnsupportedChain() public {
        uint256 unsupportedChainId = 999;

        vm.startPrank(user);
        token.approve(address(bridge), 100 ether);
        vm.expectRevert(BridgeDeposit.InvalidRoute.selector);
        bridge.depositForBridge(address(token), 100 ether, unsupportedChainId, recipient, bytes32(0));
        vm.stopPrank();
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

    function test_RevertWhen_DepositToSameChain() public {
        // Even if route was somehow enabled for same chain, deposit should revert
        vm.startPrank(user);
        token.approve(address(bridge), 100 ether);
        vm.expectRevert(BridgeDeposit.InvalidSourceChain.selector);
        bridge.depositForBridge(address(token), 100 ether, block.chainid, recipient, bytes32(0));
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Deposit with fixed fee tests
    // -------------------------------------------------------------------------

    function testDepositForBridgeWithFixedFee() public {
        uint256 fixedFee = 2 ether;
        uint256 amount = 100 ether;
        uint256 expectedBurn = amount - fixedFee;

        // Set route with fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, true, fixedFee);

        vm.startPrank(user);
        token.approve(address(bridge), amount);

        vm.expectEmit(true, true, true, true);
        emit BridgeDeposit.BridgeDepositInitiated(
            1,
            address(token),
            user,
            expectedBurn,
            fixedFee,
            DEST_CHAIN_ID,
            recipient,
            bytes32(0)
        );

        bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();

        // User balance decreased by full amount
        assertEq(token.balances(user), 10000 ether - amount);
        // Fee collector received the fee
        assertEq(token.balances(feeCollector), fixedFee);
        // Token total supply decreased by burned amount only
        assertEq(token.totalSupply(), 10000 ether - expectedBurn);
    }

    function testDepositFeeTracking() public {
        uint256 fixedFee = 2 ether;
        uint256 amount = 100 ether;

        // Set route with fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, true, fixedFee);

        // Make deposit
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();

        // Check fee tracking
        assertEq(bridge.totalFeesCollected(address(token), DEST_CHAIN_ID), fixedFee);

        // Make another deposit
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();

        // Fees should accumulate
        assertEq(bridge.totalFeesCollected(address(token), DEST_CHAIN_ID), fixedFee * 2);
    }

    function test_RevertWhen_AmountTooLowForFee() public {
        uint256 fixedFee = 10 ether;
        uint256 amount = 10 ether; // Equal to fee, should revert

        // Set route with fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, true, fixedFee);

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        vm.expectRevert(BridgeDeposit.AmountTooLowForFee.selector);
        bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertWhen_AmountLessThanFee() public {
        uint256 fixedFee = 10 ether;
        uint256 amount = 5 ether; // Less than fee

        // Set route with fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, true, fixedFee);

        vm.startPrank(user);
        token.approve(address(bridge), amount);
        vm.expectRevert(BridgeDeposit.AmountTooLowForFee.selector);
        bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();
    }

    function test_RevertWhen_FeeConfiguredButNoFeeCollector() public {
        uint256 fixedFee = 2 ether;

        // Deploy bridge without fee collector
        BridgeDeposit bridgeNoCollector = new BridgeDeposit(
            admin,
            ILimitedMinterBridge(address(limitedMinter)),
            address(0)
        );

        // Set route with fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridgeNoCollector.setBridgeRoutes(address(token), destChains, true, fixedFee);

        // Should revert because fee > 0 but feeCollector is address(0)
        vm.startPrank(user);
        token.approve(address(bridgeNoCollector), 100 ether);
        vm.expectRevert(BridgeDeposit.ZeroAddress.selector);
        bridgeNoCollector.depositForBridge(address(token), 100 ether, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();
    }

    function testDepositWithZeroFeeAndNoFeeCollector() public {
        // Deploy bridge without fee collector
        BridgeDeposit bridgeNoCollector = new BridgeDeposit(
            admin,
            ILimitedMinterBridge(address(limitedMinter)),
            address(0)
        );

        // Set route with zero fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridgeNoCollector.setBridgeRoutes(address(token), destChains, true, 0);

        // Should work because fee is 0
        vm.startPrank(user);
        token.approve(address(bridgeNoCollector), 100 ether);
        bridgeNoCollector.depositForBridge(address(token), 100 ether, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // fulfillBridgeMint tests
    // -------------------------------------------------------------------------

    function testFulfillBridgeMint() public {
        uint256 amount = 500 ether;
        uint256 sourceChainId = 1;
        bytes32 sourceTxHash = keccak256("tx-hash-123");
        uint256 sourceDepositId = 1;

        vm.prank(bridgeOperator);
        vm.expectEmit(true, true, true, true);
        emit BridgeDeposit.BridgeMintFulfilled(
            address(token),
            recipient,
            amount,
            sourceChainId,
            sourceTxHash,
            sourceDepositId
        );
        bridge.fulfillBridgeMint(address(token), recipient, amount, sourceChainId, sourceTxHash, sourceDepositId);

        assertEq(token.balances(recipient), amount);
        // Check fulfillment key (composite of chainId + txHash + depositId)
        bytes32 fulfillmentKey = keccak256(abi.encodePacked(sourceChainId, sourceTxHash, sourceDepositId));
        assertTrue(bridge.bridgeFulfilled(fulfillmentKey));
    }

    function test_RevertWhen_FulfillByNonOperator() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        vm.prank(user);
        vm.expectRevert();
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, 1);
    }

    function test_RevertWhen_FulfillAlreadyFulfilled() public {
        bytes32 sourceTxHash = keccak256("tx-hash-duplicate");
        uint256 sourceDepositId = 1;

        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, sourceDepositId);

        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.BridgeAlreadyFulfilled.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, sourceDepositId);
    }

    function test_RevertWhen_FulfillTokenNotInMinter() public {
        MockBurnableToken unregisteredToken = new MockBurnableToken();
        bytes32 sourceTxHash = keccak256("tx-hash");

        // Token not registered in LimitedMinterBridge - should revert
        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.TokenNotRegisteredInMinter.selector);
        bridge.fulfillBridgeMint(address(unregisteredToken), recipient, 100 ether, 1, sourceTxHash, 1);
    }

    function test_RevertWhen_FulfillZeroAmount() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.AmountZero.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 0, 1, sourceTxHash, 1);
    }

    function test_RevertWhen_FulfillZeroRecipient() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.InvalidRecipient.selector);
        bridge.fulfillBridgeMint(address(token), address(0), 100 ether, 1, sourceTxHash, 1);
    }

    function test_RevertWhen_FulfillWhilePaused() public {
        vm.prank(admin);
        bridge.pause();

        bytes32 sourceTxHash = keccak256("tx-hash");
        vm.prank(bridgeOperator);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, 1);
    }

    function testFulfillRespectsLimitedMinterDailyLimit() public {
        // Mint up to the daily limit
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, DAILY_LIMIT, 1, keccak256("tx-1"), 1);

        // Try to mint more - should fail due to daily limit
        vm.prank(bridgeOperator);
        vm.expectRevert(LimitedMinterBridge.ExceedsDailyMintLimit.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 1 ether, 1, keccak256("tx-2"), 2);

        // Next day should work
        vm.warp(block.timestamp + 1 days);
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 1000 ether, 1, keccak256("tx-3"), 3);
    }

    // -------------------------------------------------------------------------
    // Admin function tests
    // -------------------------------------------------------------------------

    function testSetBridgeRoutes() public {
        // Set outbound routes to multiple chains
        uint256[] memory destChains = new uint256[](2);
        destChains[0] = 137; // Polygon
        destChains[1] = 42161; // Arbitrum
        
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, true, 5 ether);

        (bool enabled1, uint256 fee1) = bridge.routeConfigs(address(token), 137);
        (bool enabled2, uint256 fee2) = bridge.routeConfigs(address(token), 42161);

        assertTrue(enabled1);
        assertTrue(enabled2);
        assertEq(fee1, 5 ether);
        assertEq(fee2, 5 ether);
    }

    function testRemoveBridgeRoute() public {
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, false, 0);

        (bool enabled,) = bridge.routeConfigs(address(token), DEST_CHAIN_ID);
        assertFalse(enabled);
    }

    function test_RevertWhen_SetRouteToSameChain() public {
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = block.chainid; // Current chain

        vm.prank(admin);
        vm.expectRevert(BridgeDeposit.InvalidSourceChain.selector);
        bridge.setBridgeRoutes(address(token), destChains, true, 0);
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
    // updateRouteFee tests
    // -------------------------------------------------------------------------

    function testUpdateRouteFee() public {
        uint256 newFee = 5 ether;

        vm.prank(feeManager);
        vm.expectEmit(true, true, false, true);
        emit BridgeDeposit.RouteFeeUpdated(address(token), DEST_CHAIN_ID, 0, newFee);
        bridge.updateRouteFee(address(token), DEST_CHAIN_ID, newFee);

        (, uint256 fee) = bridge.routeConfigs(address(token), DEST_CHAIN_ID);
        assertEq(fee, newFee);
    }

    function testUpdateRouteFeeByAdmin() public {
        // Admin also has FEE_MANAGER_ROLE from constructor
        uint256 newFee = 3 ether;

        vm.prank(admin);
        bridge.updateRouteFee(address(token), DEST_CHAIN_ID, newFee);

        (, uint256 fee) = bridge.routeConfigs(address(token), DEST_CHAIN_ID);
        assertEq(fee, newFee);
    }

    function test_RevertWhen_UpdateRouteFeeByNonFeeManager() public {
        vm.prank(user);
        vm.expectRevert();
        bridge.updateRouteFee(address(token), DEST_CHAIN_ID, 5 ether);
    }

    function test_RevertWhen_UpdateRouteFeeForDisabledRoute() public {
        // Disable the route first
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, false, 0);

        // Try to update fee on disabled route
        vm.prank(feeManager);
        vm.expectRevert(BridgeDeposit.InvalidRoute.selector);
        bridge.updateRouteFee(address(token), DEST_CHAIN_ID, 5 ether);
    }

    function test_RevertWhen_UpdateRouteFeeForNonexistentRoute() public {
        // Route that was never created
        vm.prank(feeManager);
        vm.expectRevert(BridgeDeposit.InvalidRoute.selector);
        bridge.updateRouteFee(address(token), 999, 5 ether);
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
        bridge.fulfillBridgeMint(address(token), recipient, 3000 ether, 1, keccak256("tx-1"), 1);

        (remaining, dailyMax, mintedToday) = bridge.remainingMintCapacity(address(token));
        assertEq(remaining, DAILY_LIMIT - 3000 ether);
        assertEq(dailyMax, DAILY_LIMIT);
        assertEq(mintedToday, 3000 ether);
    }

    function testRemainingMintCapacityAfterDayReset() public {
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, DAILY_LIMIT, 1, keccak256("tx-1"), 1);

        (uint256 remaining,,) = bridge.remainingMintCapacity(address(token));
        assertEq(remaining, 0);

        // Next day
        vm.warp(block.timestamp + 1 days);
        (remaining,,) = bridge.remainingMintCapacity(address(token));
        assertEq(remaining, DAILY_LIMIT);
    }

    // -------------------------------------------------------------------------
    // Same-chain fulfillment prevention tests
    // -------------------------------------------------------------------------

    function test_RevertWhen_FulfillSameChain() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        // Try to fulfill with current chain as source chain
        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.InvalidSourceChain.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, block.chainid, sourceTxHash, 1);
    }

    // -------------------------------------------------------------------------
    // Cross-chain replay prevention tests
    // -------------------------------------------------------------------------

    function testDifferentChainsSameTxHashDifferentDepositIds() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        // Fulfill from chain 1, deposit 1
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, 1);

        // Fulfill from chain 1, deposit 2 (same tx, different deposit)
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, 2);

        // Fulfill from chain 2, deposit 1 (different chain)
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 2, sourceTxHash, 1);

        assertEq(token.balances(recipient), 300 ether);
    }

    function test_RevertWhen_SameChainSameTxHashSameDepositId() public {
        bytes32 sourceTxHash = keccak256("tx-hash");

        // First fulfill
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, 1);

        // Attempt duplicate - same chain, same tx, same deposit
        vm.prank(bridgeOperator);
        vm.expectRevert(BridgeDeposit.BridgeAlreadyFulfilled.selector);
        bridge.fulfillBridgeMint(address(token), recipient, 100 ether, 1, sourceTxHash, 1);
    }

    // -------------------------------------------------------------------------
    // Route-based token support tests
    // -------------------------------------------------------------------------

    function testMultipleRoutesForToken() public {
        // Add routes to multiple chains
        uint256[] memory moreChains = new uint256[](2);
        moreChains[0] = 42161; // Arbitrum
        moreChains[1] = 10;    // Optimism
        
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), moreChains, true, 1 ether);

        // All routes should be enabled
        (bool enabled1,) = bridge.routeConfigs(address(token), DEST_CHAIN_ID);
        (bool enabled2,) = bridge.routeConfigs(address(token), 42161);
        (bool enabled3,) = bridge.routeConfigs(address(token), 10);

        assertTrue(enabled1); // from setUp
        assertTrue(enabled2);
        assertTrue(enabled3);
    }

    function testDisableSpecificRoute() public {
        // First add another route
        uint256[] memory extraChain = new uint256[](1);
        extraChain[0] = 42161;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), extraChain, true, 0);

        // Now disable just the original route
        uint256[] memory chainToDisable = new uint256[](1);
        chainToDisable[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), chainToDisable, false, 0);

        // Original route disabled, new route still enabled
        (bool enabled1,) = bridge.routeConfigs(address(token), DEST_CHAIN_ID);
        (bool enabled2,) = bridge.routeConfigs(address(token), 42161);

        assertFalse(enabled1);
        assertTrue(enabled2);
    }

    // -------------------------------------------------------------------------
    // Token rescue tests
    // -------------------------------------------------------------------------

    function testRescueTokens() public {
        // Simulate tokens accidentally sent to bridge contract
        // Use bridgeOperator to fulfill a mint to the bridge address (simulating accidental send)
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), address(bridge), 500 ether, 1, keccak256("rescue-test"), 1);

        uint256 bridgeBalanceBefore = token.balances(address(bridge));
        assertEq(bridgeBalanceBefore, 500 ether);

        // Admin rescues the tokens
        vm.prank(admin);
        bridge.rescueTokens(address(token), recipient, 500 ether);

        assertEq(token.balances(address(bridge)), 0);
        assertEq(token.balances(recipient), 500 ether);
    }

    function test_RevertWhen_RescueByNonAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        bridge.rescueTokens(address(token), recipient, 100 ether);
    }

    function test_RevertWhen_RescueToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(BridgeDeposit.ZeroAddress.selector);
        bridge.rescueTokens(address(token), address(0), 100 ether);
    }

    function test_RevertWhen_RescueZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(BridgeDeposit.AmountZero.selector);
        bridge.rescueTokens(address(token), recipient, 0);
    }

    // -------------------------------------------------------------------------
    // Conservation tracking tests
    // -------------------------------------------------------------------------

    function testTotalBurnedToAfterDeposit() public {
        uint256 amount = 100 ether;

        // Initial stats should be zero
        (uint256 burnedBefore,) = bridge.getBridgeStats(address(token), DEST_CHAIN_ID);
        assertEq(burnedBefore, 0);

        // Make deposit
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();

        // Verify totalBurnedTo incremented
        (uint256 burnedAfter,) = bridge.getBridgeStats(address(token), DEST_CHAIN_ID);
        assertEq(burnedAfter, amount);
    }

    function testTotalBurnedToWithFee() public {
        uint256 fixedFee = 5 ether;
        uint256 amount = 100 ether;
        uint256 expectedBurn = amount - fixedFee;

        // Set route with fee
        uint256[] memory destChains = new uint256[](1);
        destChains[0] = DEST_CHAIN_ID;
        vm.prank(admin);
        bridge.setBridgeRoutes(address(token), destChains, true, fixedFee);

        // Make deposit
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.depositForBridge(address(token), amount, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();

        // totalBurnedTo should only track burned amount, not fee
        (uint256 burned,) = bridge.getBridgeStats(address(token), DEST_CHAIN_ID);
        assertEq(burned, expectedBurn);
    }

    function testTotalMintedFromAfterFulfill() public {
        uint256 amount = 500 ether;
        uint256 sourceChainId = 1;

        // Initial stats should be zero
        (, uint256 mintedBefore) = bridge.getBridgeStats(address(token), sourceChainId);
        assertEq(mintedBefore, 0);

        // Fulfill bridge mint
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, amount, sourceChainId, keccak256("tx-1"), 1);

        // Verify totalMintedFrom incremented
        (, uint256 mintedAfter) = bridge.getBridgeStats(address(token), sourceChainId);
        assertEq(mintedAfter, amount);
    }

    function testConservationStatsAccumulate() public {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;

        // Multiple deposits
        vm.startPrank(user);
        token.approve(address(bridge), amount1 + amount2);
        bridge.depositForBridge(address(token), amount1, DEST_CHAIN_ID, recipient, bytes32(0));
        bridge.depositForBridge(address(token), amount2, DEST_CHAIN_ID, recipient, bytes32(0));
        vm.stopPrank();

        // Verify accumulation
        (uint256 burned,) = bridge.getBridgeStats(address(token), DEST_CHAIN_ID);
        assertEq(burned, amount1 + amount2);

        // Multiple fulfillments from same source chain
        vm.startPrank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, amount1, 1, keccak256("tx-1"), 1);
        bridge.fulfillBridgeMint(address(token), recipient, amount2, 1, keccak256("tx-2"), 2);
        vm.stopPrank();

        (, uint256 minted) = bridge.getBridgeStats(address(token), 1);
        assertEq(minted, amount1 + amount2);
    }

    function testBridgeStatsPerChainIsolation() public {
        uint256 amount = 100 ether;

        // Fulfill from chain 1
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, amount, 1, keccak256("tx-1"), 1);

        // Fulfill from chain 2
        vm.prank(bridgeOperator);
        bridge.fulfillBridgeMint(address(token), recipient, amount * 2, 2, keccak256("tx-2"), 1);

        // Verify per-chain isolation
        (, uint256 mintedFromChain1) = bridge.getBridgeStats(address(token), 1);
        (, uint256 mintedFromChain2) = bridge.getBridgeStats(address(token), 2);

        assertEq(mintedFromChain1, amount);
        assertEq(mintedFromChain2, amount * 2);
    }

    // -------------------------------------------------------------------------
    // Fee collector tests
    // -------------------------------------------------------------------------

    function testSetFeeCollector() public {
        address newFeeCollector = address(0x123);

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit BridgeDeposit.FeeCollectorUpdated(feeCollector, newFeeCollector);
        bridge.setFeeCollector(newFeeCollector);

        assertEq(bridge.feeCollector(), newFeeCollector);
    }

    function testSetFeeCollectorToZero() public {
        vm.prank(admin);
        bridge.setFeeCollector(address(0));

        assertEq(bridge.feeCollector(), address(0));
    }

    function test_RevertWhen_SetFeeCollectorByNonAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        bridge.setFeeCollector(address(0x123));
    }

    function testFeeCollectorSetInConstructor() public {
        assertEq(bridge.feeCollector(), feeCollector);
    }

    // -------------------------------------------------------------------------
    // FEE_MANAGER_ROLE tests
    // -------------------------------------------------------------------------

    function testFeeManagerRoleGrantedToAdminInConstructor() public {
        assertTrue(bridge.hasRole(bridge.FEE_MANAGER_ROLE(), admin));
    }

    function testGrantFeeManagerRole() public {
        address newFeeManager = address(0x999);
        bytes32 feeManagerRole = bridge.FEE_MANAGER_ROLE();

        vm.prank(admin);
        bridge.grantRole(feeManagerRole, newFeeManager);

        assertTrue(bridge.hasRole(feeManagerRole, newFeeManager));
    }
}
