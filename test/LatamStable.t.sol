// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {LatamStable} from "../src/LatamStable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LatamStableTest is Test {
    LatamStable public latamStable;
    address public owner;
    address public user;
    string public constant TOKEN_NAME = "Latam Stable";
    string public constant TOKEN_SYMBOL = "LATAM";

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        // Deploy implementation
        LatamStable implementation = new LatamStable();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            LatamStable.initialize.selector,
            owner,
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
        assertEq(latamStable.owner(), owner);
        assertEq(latamStable.totalSupply(), 0);
    }

    function test_Mint() public {
        uint256 amount = 1000 ether;
        
        vm.prank(owner);
        latamStable.mint(user, amount);

        assertEq(latamStable.balanceOf(user), amount);
        assertEq(latamStable.totalSupply(), amount);
    }

    function test_Mint_RevertIfNotOwner() public {
        uint256 amount = 1000 ether;
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        latamStable.mint(user, amount);
    }

    function test_Burn() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 500 ether;
        
        // Mint tokens first
        vm.prank(owner);
        latamStable.mint(user, mintAmount);

        // Burn tokens
        vm.prank(user);
        latamStable.burn(burnAmount);

        assertEq(latamStable.balanceOf(user), mintAmount - burnAmount);
        assertEq(latamStable.totalSupply(), mintAmount - burnAmount);
    }

    function test_Pause() public {
        // Mint tokens first
        vm.prank(owner);
        latamStable.mint(user, 1000 ether);

        // Pause the contract
        vm.prank(owner);
        latamStable.pause();

        // Try to transfer while paused
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        latamStable.transfer(owner, 500 ether);
    }

    function test_Unpause() public {
        // Pause first
        vm.prank(owner);
        latamStable.pause();

        // Unpause
        vm.prank(owner);
        latamStable.unpause();

        // Mint and transfer should work again
        vm.prank(owner);
        latamStable.mint(user, 1000 ether);

        vm.prank(user);
        latamStable.transfer(owner, 500 ether);

        assertEq(latamStable.balanceOf(owner), 500 ether);
        assertEq(latamStable.balanceOf(user), 500 ether);
    }

    function test_Pause_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        latamStable.pause();
    }

    function test_Unpause_RevertIfNotOwner() public {
        vm.prank(owner);
        latamStable.pause();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        latamStable.unpause();
    }
} 