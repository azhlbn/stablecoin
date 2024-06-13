// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

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

    function test_sync() public {
        assertEq(token.deviation(), 0);
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(token.balanceOf(deployer), 1_000_000 ether);
        assertEq(lp.balanceOf(deployer), 1_000_000 ether);
        assertEq(token.maxDeviation(), 100_000 ether);

        lp.burn(deployer, 100_000 ether);
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(lp.balanceOf(deployer), 900_000 ether);

        token.sync();
        assertEq(token.totalSupply(), 900_000 ether);
        assertEq(lp.balanceOf(deployer), 900_000 ether);
        assertEq(token.balanceOf(deployer), 900_000 ether);

        lp.mint(deployer, 50_000 ether);
        assertEq(lp.balanceOf(deployer), 950_000 ether);
        assertEq(token.totalSupply(), 900_000 ether);
        assertEq(token.balanceOf(deployer), 900_000 ether);

        token.sync();
        assertEq(token.totalSupply(), 950_000 ether);
        assertEq(lp.balanceOf(deployer), 950_000 ether);
        assertEq(token.balanceOf(deployer), 950_000 ether);

        lp.burn(deployer, 900_000 ether);
        assertEq(lp.balanceOf(deployer), 50_000 ether);
        assertEq(token.totalSupply(), 950_000 ether);
        assertEq(token.balanceOf(deployer), 950_000 ether);

        token.sync();
        assertEq(token.totalSupply(), 50_000 ether);
        assertEq(lp.balanceOf(deployer), 50_000 ether);
        assertEq(token.balanceOf(deployer), 50_000 ether);

        switchPrank(deployer);
        token.transfer(user1, 10_000 ether);
        lp.burn(deployer, 45_000 ether);
        assertEq(lp.balanceOf(deployer), 5_000 ether);
        assertEq(token.totalSupply(), 50_000 ether);
        assertEq(token.balanceOf(deployer), 40_000 ether);

        // case when owner hasn't enough tokens for burn
        // as result we have the gap equal to 5_000 ether 
        token.sync();
        assertEq(lp.balanceOf(deployer), 5_000 ether);
        assertEq(token.totalSupply(), 10_000 ether);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(user1), 10_000 ether);
    }

    function test_ok() public {
        assertTrue(token.ok());

        lp.burn(deployer, 1 ether);
        assertFalse(token.ok());

        token.sync();
        assertTrue(token.ok());
    }

    function test_currentPeg() public {
        assertEq(token.currentPeg(), 1e18);
        uint256 initialSupply = token.totalSupply();

        switchPrank(deployer);
        token.mint(user1, 1000 ether);

        uint256 peg = (initialSupply + 1000 ether) * 1e18 / lp.balanceOf(deployer);

        assertEq(token.currentPeg(), peg);
    }

    function test_revoke_renounce_role() public {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));

        switchPrank(deployer);
        vm.expectRevert(IPeggedAsset.NotAllowed.selector);
        token.revokeRole(bytes32(0), deployer); // bytes32(0) equal to DEFAULT_ADMIN_ROLE

        vm.expectRevert(IPeggedAsset.NotAllowed.selector);
        token.renounceRole(bytes32(0), deployer);

        token.grantRole(token.ADMIN(), user1);
        assertTrue(token.hasRole(token.ADMIN(), user1));

        switchPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, 
                user1, 
                token.DEFAULT_ADMIN_ROLE()
            )
        );
        token.revokeRole(keccak256("ADMIN"), user1);
    
        switchPrank(deployer);
        token.revokeRole(token.ADMIN(), user1);
        assertFalse(token.hasRole(token.ADMIN(), user1));

        token.grantRole(token.ADMIN(), user1);
        switchPrank(user1);
        token.renounceRole(token.ADMIN(), user1);
        assertFalse(token.hasRole(token.ADMIN(), user1));
    }

    function test_owner_change_logic() public {
        assertEq(token.owner(), deployer);

        switchPrank(deployer);
        vm.expectRevert(IPeggedAsset.ZeroAddress.selector);
        token.grantOwnership(address(0));

        vm.expectRevert(IPeggedAsset.OwnerMatch.selector);
        token.grantOwnership(deployer);

        token.grantOwnership(user2);
        switchPrank(user3);
        vm.expectRevert(IPeggedAsset.NotGrantedOwner.selector);
        token.claimOwnership();

        switchPrank(user2);
        token.claimOwnership();
        assertEq(token.owner(), user2);
        assertFalse(token.hasRole(token.SUPER_ADMIN(), deployer));
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(token.hasRole(token.SUPER_ADMIN(), user2));
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), user2));

        token.setMaxDepeg(1);
        assertEq(token.maxDepeg(), 1);
    }

    function test_add_remove_to_blacklist() public {
        switchPrank(user1);
        vm.expectRevert(IPeggedAsset.OnlyForAdmin.selector);
        token.addToBlacklist(user3);

        // add and remove from blacklist by owner
        switchPrank(deployer);
        token.addToBlacklist(user3);
        assertTrue(token.hasRole(token.BLACKLISTED(), user3));
        token.removeFromBlacklist(user3);
        assertFalse(token.hasRole(token.BLACKLISTED(), user3));

        // add admin role for user2
        token.grantRole(token.ADMIN(), user2);
        assertTrue(token.hasRole(token.ADMIN(), user2));

        // add and remove from blacklist by admin
        switchPrank(user2);
        token.addToBlacklist(user3);
        assertTrue(token.hasRole(token.BLACKLISTED(), user3));
        token.removeFromBlacklist(user3);
        assertFalse(token.hasRole(token.BLACKLISTED(), user3));
    }

    function test_setMaxDepeg() public {
        assertEq(token.maxDepeg(), 100_000 ether);

        // check if allowed only for owner
        switchPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, 
                user1, 
                token.SUPER_ADMIN()
            )
        );
        token.setMaxDepeg(50_000 ether);

        switchPrank(deployer);
        token.setMaxDepeg(50_000 ether);
        assertEq(token.maxDepeg(), 50_000 ether);
    }

    function test_setMinOwnerBalance() public {
        assertEq(lp.balanceOf(deployer), 1_000_000 ether);
        assertEq(token.minOwnerBalance(), 5000);

        switchPrank(deployer);
        token.transfer(user1, 500_000 ether);
        vm.expectRevert(IPeggedAsset.MinOwnerBalanceCrossed.selector);
        token.transfer(user1, 1);

        switchPrank(user1);
        token.transfer(deployer, 500_000 ether);

        switchPrank(deployer);
        token.setMinOwnerBalance(7500);        
        assertEq(token.minOwnerBalance(), 7500);

        token.transfer(user1, 250_000 ether);
        vm.expectRevert(IPeggedAsset.MinOwnerBalanceCrossed.selector);
        token.transfer(user1, 1);
    }

    function test_setMaxDeviation() public {
        assertEq(token.maxDeviation(), 100_000 ether);

        switchPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, 
                user1, 
                token.SUPER_ADMIN()
            )
        );
        token.setMaxDeviation(50_000 ether);

        switchPrank(deployer);
        token.setMaxDeviation(50_000 ether);
        assertEq(token.maxDeviation(), 50_000 ether);

        token.mint(deployer, 50_000 ether);
        vm.expectRevert(IPeggedAsset.TooLargeDeviation.selector);
        token.mint(deployer, 1);

        token.burn(deployer, 100_000 ether);
        vm.expectRevert(IPeggedAsset.TooLargeDeviation.selector);
        token.burn(deployer, 1);
    }

    function test_burn() public {
        switchPrank(deployer);
        token.mint(user1, 10 ether);
        assertEq(token.deviation(), 10 ether);

        // check if the only owner can call the burn function
        switchPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, 
                user1, 
                token.SUPER_ADMIN()
            )
        );
        token.burn(user1, 1 ether);

        switchPrank(deployer);
        token.burn(user1, 10 ether);
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.deviation(), 0);

        token.burn(deployer, 100_000 ether);
        assertEq(token.balanceOf(deployer), 900_000 ether);
        vm.expectRevert(IPeggedAsset.TooLargeDeviation.selector);
        token.burn(deployer, 1);

        token.mint(deployer, 100_000 ether);
        assertEq(token.deviation(), 0);
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(lp.balanceOf(deployer), 1_000_000 ether);
        assertEq(token.balanceOf(deployer), 1_000_000 ether);

        token.transfer(user1, 500_000 ether);
        assertEq(token.balanceOf(deployer), 500_000 ether);

        // check on impossibility of burn owner's tokens when minOwnerBalance reached
        vm.expectRevert(IPeggedAsset.MinOwnerBalanceCrossed.selector);
        token.burn(deployer, 1);
        assertEq(token.deviation(), 0);
    }

    function test_mint() public {
        assertEq(token.deviation(), 0);
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(lp.balanceOf(deployer), 1_000_000 ether);
        assertEq(token.maxDeviation(), 100_000 ether);

        // check if the only owner can call the mint function
        switchPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, 
                user1, 
                token.SUPER_ADMIN()
            )
        );
        token.mint(user1, 1 ether);

        switchPrank(deployer);
        token.mint(user1, 10_000 ether);
        assertEq(token.deviation(), 10_000 ether);
        token.mint(user2, 10_000 ether);
        assertEq(token.deviation(), 20_000 ether);
        token.burn(deployer, 10_000 ether);
        assertEq(token.deviation(), 10_000 ether);
        token.mint(user1, 90_000 ether);

        vm.expectRevert(IPeggedAsset.TooLargeDeviation.selector);
        token.mint(user1, 1);

        token.burn(deployer, 1);
        token.mint(user1, 1);
        assertEq(token.balanceOf(user1), 100_000 ether + 1);
        assertEq(uint256(token.deviation()), token.maxDeviation());
    }

    function test_check_validity() public {
        switchPrank(deployer);
        token.transfer(user1, 1 ether);

        // add user1 to blacklist
        token.grantRole(token.BLACKLISTED(), user1);

        switchPrank(user1);
        vm.expectRevert(IPeggedAsset.Blacklisted.selector);
        token.transfer(user2, 1 ether);

        // remove user1 from blacklist
        switchPrank(deployer);
        token.revokeRole(token.BLACKLISTED(), user1);

        // check if the user1 is able to transfer tokens
        switchPrank(user1);
        token.transfer(deployer, 1 ether);
        assertEq(token.balanceOf(user1), 0);

        // current state of lp tokens and stable tokens
        assertEq(lp.balanceOf(deployer), 1_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000 ether);

        switchPrank(deployer);
        vm.expectRevert(IPeggedAsset.MinOwnerBalanceCrossed.selector);
        token.transfer(user1, 500_000 ether + 1);
        token.transfer(user1, 500_000 ether);
        assertEq(token.balanceOf(deployer), lp.balanceOf(deployer) / 2);
        vm.expectRevert(IPeggedAsset.MinOwnerBalanceCrossed.selector);
        token.transfer(user1, 1);

        lp.burn(deployer, 500_000 ether);
        assertEq(lp.balanceOf(deployer), 500_000 ether);
        vm.expectRevert(IPeggedAsset.MinOwnerBalanceCrossed.selector);
        token.transfer(user1, 250_000 ether + 1);

        // too large difference between totalSupply and owner's lp token balance
        vm.expectRevert(IPeggedAsset.MaxDepegReached.selector);
        token.transfer(user1, 250_000 ether);

        token.sync();
        assertEq(lp.balanceOf(deployer), token.totalSupply());
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(user1), lp.balanceOf(deployer));

        switchPrank(user1);
        token.transfer(deployer, token.balanceOf(user1));
        assertEq(token.balanceOf(deployer), lp.balanceOf(deployer));
    }

    function test_transferFrom() public {
        _transferTokens();
        token.approve(user1, 1 ether);
        token.approve(user2, 1 ether);
        token.approve(user3, 1 ether);

        switchPrank(user1);
        token.transferFrom(deployer, user1, 1 ether);

        switchPrank(user2);
        token.transferFrom(deployer, user2, 1 ether);

        switchPrank(user3);
        token.transferFrom(deployer, user3, 1 ether);

        assertEq(token.balanceOf(user1), 2 ether);
        assertEq(token.balanceOf(user2), 2 ether);
        assertEq(token.balanceOf(user3), 2 ether);
    }

    function test_transfer() public {
        _transferTokens();
        assertEq(token.balanceOf(user1), 1 ether);
        assertEq(token.balanceOf(user2), 1 ether);
        assertEq(token.balanceOf(user3), 1 ether);

        switchPrank(user1);
        token.transfer(user3, 0.5 ether);

        switchPrank(user2);
        token.transfer(user3, 0.5 ether);

        assertEq(token.balanceOf(user3), 2 ether);
    }

    function test_deploy() public view {
        uint256 lpSupply = lp.balanceOf(deployer);
        assertEq(address(token.trackedToken()), address(lp));
        assertEq(token.owner(), deployer);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "STB");
        assertEq(lpSupply, 1_000_000 ether);
        assertEq(token.balanceOf(deployer), 1_000_000 ether);
        assertEq(token.maxDeviation(), lpSupply / 10);
        assertEq(token.minOwnerBalance(), 5000);
        assertEq(token.maxDepeg(), lpSupply / 10);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(token.hasRole(token.SUPER_ADMIN(), deployer));
    }

    function _transferTokens() internal {
        switchPrank(deployer);
        token.transfer(user1, 1 ether);
        token.transfer(user2, 1 ether);
        token.transfer(user3, 1 ether);
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
