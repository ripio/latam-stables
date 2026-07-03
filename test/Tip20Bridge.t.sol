// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ITip20LimitedMinterBridge, Tip20BridgeDeposit} from "../src/Tip20BridgeDeposit.sol";
import {Tip20LimitedMinterBridge} from "../src/Tip20LimitedMinterBridge.sol";

contract MockTip20 {
    string public name = "Mock TIP-20";
    string public symbol = "MTIP";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    bool public redirectMints;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TransferWithMemo(address indexed from, address indexed to, uint256 amount, bytes32 indexed memo);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function mintForTest(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function mintWithMemo(address to, uint256 amount, bytes32 memo) external {
        if (!redirectMints) {
            balanceOf[to] += amount;
            totalSupply += amount;
        }
        emit TransferWithMemo(address(0), to, amount, memo);
    }

    function mint(address to, uint256 amount) external {
        if (!redirectMints) {
            balanceOf[to] += amount;
            totalSupply += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function burnWithMemo(uint256 amount, bytes32 memo) external {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit TransferWithMemo(msg.sender, address(0), amount, memo);
    }

    function burn(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    function setRedirectMints(bool enabled) external {
        redirectMints = enabled;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract Tip20BridgeTest is Test {
    address internal admin = address(0xA11CE);
    address internal operator = address(0xB0B);
    address internal user = address(0xCAFE);
    address internal recipient = address(0xD00D);
    address internal feeCollector = address(0xFEE);

    uint256 internal destinationChainId = 4217;
    uint256 internal sourceChainId = 1;
    uint256 internal fixedFee = 10_000;
    bytes32 internal depositMemo = bytes32(uint256(1));
    bytes32 internal sourceTxHash = bytes32(uint256(2));
    bytes32 internal mintMemo = bytes32(uint256(3));
    bytes32 internal secondSourceTxHash = bytes32(uint256(4));

    MockTip20 internal token;
    Tip20LimitedMinterBridge internal minterBridge;
    Tip20BridgeDeposit internal bridgeDeposit;

    function setUp() public {
        token = new MockTip20();
        token.mintForTest(user, 2_000_000);

        minterBridge = new Tip20LimitedMinterBridge(admin, admin, admin);
        bridgeDeposit = new Tip20BridgeDeposit(admin, ITip20LimitedMinterBridge(address(minterBridge)), feeCollector);

        vm.startPrank(admin);
        minterBridge.grantRole(minterBridge.MINTER_ROLE(), address(bridgeDeposit));
        minterBridge.registerToken(address(token), 10_000_000);
        bridgeDeposit.grantRole(bridgeDeposit.BRIDGE_OPERATOR_ROLE(), operator);

        uint256[] memory destChainIds = new uint256[](1);
        destChainIds[0] = destinationChainId;
        bridgeDeposit.setBridgeRoutes(address(token), destChainIds, true, fixedFee);
        vm.stopPrank();

        vm.prank(user);
        token.approve(address(bridgeDeposit), type(uint256).max);
    }

    function testDepositForBridgeBurnsAndAccounts() public {
        vm.prank(user);
        uint256 depositId =
            bridgeDeposit.depositForBridge(address(token), 1_000_000, destinationChainId, recipient, depositMemo);

        assertEq(depositId, 1);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.balanceOf(address(bridgeDeposit)), 0);
        assertEq(token.balanceOf(feeCollector), fixedFee);
        assertEq(bridgeDeposit.totalBurnedTo(address(token), destinationChainId), 990_000);
        assertEq(bridgeDeposit.totalFeesCollected(address(token), destinationChainId), fixedFee);
        assertEq(bridgeDeposit.nextDepositId(), 2);
    }

    function testDepositForBridgeWithoutMemoBurnsAndAccounts() public {
        vm.prank(user);
        uint256 depositId = bridgeDeposit.depositForBridge(address(token), 1_000_000, destinationChainId, recipient);

        assertEq(depositId, 1);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.balanceOf(address(bridgeDeposit)), 0);
        assertEq(token.balanceOf(feeCollector), fixedFee);
        assertEq(bridgeDeposit.totalBurnedTo(address(token), destinationChainId), 990_000);
        assertEq(bridgeDeposit.totalFeesCollected(address(token), destinationChainId), fixedFee);
        assertEq(bridgeDeposit.nextDepositId(), 2);
    }

    function testDepositForBridgeWithMemoBurnsAndAccounts() public {
        vm.prank(user);
        uint256 depositId =
            bridgeDeposit.depositForBridgeWithMemo(address(token), 1_000_000, destinationChainId, recipient, depositMemo);

        assertEq(depositId, 1);
        assertEq(token.balanceOf(user), 1_000_000);
        assertEq(token.balanceOf(address(bridgeDeposit)), 0);
        assertEq(token.balanceOf(feeCollector), fixedFee);
        assertEq(bridgeDeposit.totalBurnedTo(address(token), destinationChainId), 990_000);
        assertEq(bridgeDeposit.totalFeesCollected(address(token), destinationChainId), fixedFee);
        assertEq(bridgeDeposit.nextDepositId(), 2);
    }

    function testFulfillBridgeMintMintsAndPreventsReplay() public {
        vm.prank(operator);
        bridgeDeposit.fulfillBridgeMint(address(token), recipient, 990_000, sourceChainId, sourceTxHash, 1, mintMemo);

        assertEq(token.balanceOf(recipient), 990_000);
        assertEq(bridgeDeposit.totalMintedFrom(address(token), sourceChainId), 990_000);

        vm.prank(operator);
        vm.expectRevert(Tip20BridgeDeposit.BridgeAlreadyFulfilled.selector);
        bridgeDeposit.fulfillBridgeMint(address(token), recipient, 990_000, sourceChainId, sourceTxHash, 1, mintMemo);
    }

    function testFulfillBridgeMintWithoutMemoMintsAndPreventsReplay() public {
        vm.prank(operator);
        bridgeDeposit.fulfillBridgeMint(address(token), recipient, 990_000, sourceChainId, sourceTxHash, 1);

        assertEq(token.balanceOf(recipient), 990_000);
        assertEq(bridgeDeposit.totalMintedFrom(address(token), sourceChainId), 990_000);

        vm.prank(operator);
        vm.expectRevert(Tip20BridgeDeposit.BridgeAlreadyFulfilled.selector);
        bridgeDeposit.fulfillBridgeMint(address(token), recipient, 990_000, sourceChainId, sourceTxHash, 1);
    }

    function testFulfillBridgeMintWithMemoMintsAndPreventsReplay() public {
        vm.prank(operator);
        bridgeDeposit.fulfillBridgeMintWithMemo(address(token), recipient, 990_000, sourceChainId, sourceTxHash, 1, mintMemo);

        assertEq(token.balanceOf(recipient), 990_000);
        assertEq(bridgeDeposit.totalMintedFrom(address(token), sourceChainId), 990_000);

        vm.prank(operator);
        vm.expectRevert(Tip20BridgeDeposit.BridgeAlreadyFulfilled.selector);
        bridgeDeposit.fulfillBridgeMintWithMemo(address(token), recipient, 990_000, sourceChainId, sourceTxHash, 1, mintMemo);
    }

    function testFulfillBridgeMintRevertsOnRedirectedDelivery() public {
        token.setRedirectMints(true);

        vm.prank(operator);
        vm.expectRevert(Tip20LimitedMinterBridge.UnexpectedTokenDelivery.selector);
        bridgeDeposit.fulfillBridgeMint(
            address(token), recipient, 990_000, sourceChainId, secondSourceTxHash, 2, mintMemo
        );
    }
}
