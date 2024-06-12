// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {Test, console} from "forge-std/Test.sol";
import {PeggedAsset} from "../src/PeggedAsset.sol";
import {MockLpToken} from "./mocs/MockLpToken.sol";
import {IPeggedAsset} from "interfaces/IPeggedAsset.sol";

contract PeggedAssetTest is Test {
    ProxyAdmin admin;

    TransparentUpgradeableProxy proxy;
    PeggedAsset implementation;
    PeggedAsset token;

    MockLpToken lp;

    address user1;
    address user2;
    address user3;

    address deployer;

    function setUp() public {
        deployer = vm.addr(99);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);

        _deploy();
    }

    function test_deploy() public {
        uint256 lpSupply = lp.balanceOf(deployer);
        assertEq(address(token.trackedToken()), address(lp));
        assertEq(token.owner(), deployer);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "STB");
        assertEq(lpSupply, 1_000_000 ether);
        assertEq(token.balanceOf(deployer), 1_000_000 ether);
        assertEq(token.maxDeviation(), lpSupply / 10);
        assertEq(token.minOwnerBalance(), lpSupply / 2);
        assertEq(token.maxDepeg(), lpSupply / 10);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(token.hasRole(token.SUPER_ADMIN(), deployer));
    }

    function test_transfer() public {
        switchPrank(deployer);
        token.transfer(user1, 1 ether);
        token.transfer(user2, 1 ether);
        token.transfer(user3, 1 ether);
        assertEq(token.balanceOf(user1), 1 ether);
        assertEq(token.balanceOf(user2), 1 ether);
        assertEq(token.balanceOf(user3), 1 ether);

        // add user1 to blacklist
        token.grantRole(token.BLACKLISTED(), user1);

        switchPrank(user1);
        vm.expectRevert(IPeggedAsset.Blacklisted.selector);
        token.transfer(user2, 1 ether);

        // remove user1 from blacklist
        switchPrank(deployer);
        token.revokeRole(token.BLACKLISTED(), user1);

        switchPrank(user1);
        token.transfer(user2, 1 ether);
        assertEq(token.balanceOf(user1), 0);
    }

    function _deploy() internal {
        switchPrank(deployer);

        admin = new ProxyAdmin(deployer);

        lp = new MockLpToken("LP token", "LP");

        implementation = new PeggedAsset();
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(admin),
            ""
        );

        token = PeggedAsset(address(proxy));
        token.initialize(IERC20(lp), deployer, "Stablecoin", "STB");
    }

    function switchPrank(address user) internal {
        vm.stopPrank();
        vm.startPrank(user);
    }
}
