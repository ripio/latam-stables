// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {LatamStable} from "../src/LatamStable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LatamStableTest is Test {
    LatamStable public latamStable;
    address public admin;
    address public user;
    string public constant TOKEN_NAME = "Latam Stable";
    string public constant TOKEN_SYMBOL = "LATAM";

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");

        // Deploy implementation
        LatamStable implementation = new LatamStable();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            LatamStable.initialize.selector,
            admin, // defaultAdmin
            admin, // pauser
            admin, // minter
            admin, // upgrader
            TOKEN_NAME,
            TOKEN_SYMBOL
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        // Initialize contract
        latamStable = LatamStable(address(proxy));
    }

    function test_Initialization() view public {
        assertEq(latamStable.name(), TOKEN_NAME);
        assertEq(latamStable.symbol(), TOKEN_SYMBOL);
        assertEq(latamStable.totalSupply(), 0);
    }

    function test_Mint() public {
        uint256 amount = 1000 ether;
        
        vm.prank(admin);
        latamStable.mint(user, amount);

        assertEq(latamStable.balanceOf(user), amount);
        assertEq(latamStable.totalSupply(), amount);
    }

    function test_Mint_RevertIfNotMinter() public {
        uint256 amount = 1000 ether;
        
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", user, latamStable.MINTER_ROLE()));
        latamStable.mint(user, amount);
        vm.stopPrank();
    }

    function test_Burn() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 500 ether;
        
        // Mint tokens first
        vm.prank(admin);
        latamStable.mint(user, mintAmount);

        // Burn tokens
        vm.prank(user);
        latamStable.burn(burnAmount);

        assertEq(latamStable.balanceOf(user), mintAmount - burnAmount);
        assertEq(latamStable.totalSupply(), mintAmount - burnAmount);
    }

    function test_Pause() public {
        // Mint tokens first
        vm.prank(admin);
        latamStable.mint(user, 1000 ether);

        // Pause the contract
        vm.prank(admin);
        latamStable.pause();

        // Try to transfer while paused
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        latamStable.transfer(admin, 500 ether);
    }

    function test_Unpause() public {
        // Pause first
        vm.prank(admin);
        latamStable.pause();

        // Unpause
        vm.prank(admin);
        latamStable.unpause();

        // Mint and transfer should work again
        vm.prank(admin);
        latamStable.mint(user, 1000 ether);

        vm.prank(user);
        latamStable.transfer(admin, 500 ether);

        assertEq(latamStable.balanceOf(admin), 500 ether);
        assertEq(latamStable.balanceOf(user), 500 ether);
    }

    function test_Pause_RevertIfNotPauser() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", user, latamStable.PAUSER_ROLE()));
        latamStable.pause();
        vm.stopPrank();
    }

    function test_Unpause_RevertIfNotPauser() public {
        vm.prank(admin);
        latamStable.pause();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", user, latamStable.PAUSER_ROLE()));
        latamStable.unpause();
        vm.stopPrank();
    }
} 