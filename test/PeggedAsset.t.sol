// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TransparentUpgradeableProxy } from "@openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { Test, console } from "forge-std/Test.sol";
import { PeggedAsset } from "../src/PeggedAsset.sol";
import { MockTrackedToken } from "./mocs/MockTrackedToken.sol";
import { IPeggedAsset } from "interfaces/IPeggedAsset.sol";

import { IUniswapV2Factory } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Router02 } from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { WETH } from "lib/solmate/src/tokens/WETH.sol";

import { Deployer } from "test/util/Deployer.sol";


contract PeggedAssetTest is Test {
    ProxyAdmin admin;

    TransparentUpgradeableProxy proxy;
    PeggedAsset implementation;
    PeggedAsset token;

    MockTrackedToken lp;
    MockTrackedToken tokenA;
    MockTrackedToken tokenB;

    address userA;
    address userB;
    address userC;
    address deployer;

    // uni
    IUniswapV2Factory factory;
    IUniswapV2Pair pair;
    IUniswapV2Router02 router;
    WETH weth;

    function setUp() public {
        deployer = vm.addr(99);
        userA = vm.addr(1);
        userB = vm.addr(2);
        userC = vm.addr(3);

        _deploy();
    }

    function test_Deployed() public view {
        assertEq(address(token.tokenA()), address(tokenA));
        assertEq(address(token.tokenB()), address(tokenB));
        assertEq(token.owner(), deployer);
        assertEq(token.decimals(), 6);
        assertEq(address(token.router()), address(router));
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(token.hasRole(token.SUPER_ADMIN(), deployer));
    }

    function test_Liquidity_Adding() public {
        switchPrank(userA);
        ( , , uint256 addedLiquidity) = token.addLiquidity(1e8);
        pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        assertEq(token.totalSupply(), addedLiquidity * 2);
        assertEq(address(token.pair()), address(pair));
        assertEq(pair.balanceOf(address(token)), addedLiquidity);
    }

    function test_Liquidity_SurplusSending() public {
        uint256 initialBalance = 100e18;
        uint256 liquidity = 9999999999;

        switchPrank(userA);
        (uint256 addedA, uint256 addedB, ) = token.addLiquidity(liquidity);
        pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        assertEq(tokenA.balanceOf(userA), initialBalance - addedA);
        assertEq(tokenB.balanceOf(userA), initialBalance - addedB);
    }

    function test_Liquidity_Removing() public {
        test_Liquidity_Adding();

        switchPrank(deployer);
        uint256 bal = token.balanceOf(address(token));

        // issue entire token balance for userA
        token.issue(userA, bal);
        assertEq(token.balanceOf(userA), bal);
        assertEq(pair.balanceOf(userA), 0);
        
        switchPrank(userA);
        token.transfer(userB, 1e6);
        assertEq(token.balanceOf(userB), 1e6);

        switchPrank(userB);
        // check userB hasn't any liquidity tokens yet
        assertEq(tokenA.balanceOf(userB), 0);
        assertEq(tokenB.balanceOf(userB), 0);

        // remove liquidity by userB and check if liquidity token balance was increased
        (uint256 removedA, uint256 removedB) = token.removeLiquidity(1e6);
        assertGt(tokenA.balanceOf(userB), 0);
        assertGt(tokenB.balanceOf(userB), 0);
        assertEq(tokenA.balanceOf(userB), removedA);
        assertEq(tokenB.balanceOf(userB), removedB);
        assertEq(token.totalSupply(), pair.balanceOf(address(token)) * 2);
    }

    function test_AddLP() public {
        switchPrank(userA);

        // add liquidity to uni v2 pool directly by userA
        ( , , uint256 addedLiq) = router.addLiquidity(
            address(tokenA), 
            address(tokenB), 
            1e18, 
            1e18, 
            0, 
            0, 
            userA, 
            block.timestamp + 1000
        );        
        pair = IUniswapV2Pair(factory.getPair(address(tokenA), address(tokenB)));

        // check if liquidity added correctly
        assertEq(pair.balanceOf(userA), addedLiq);
        assertEq(pair.balanceOf(address(token)), 0);        
        assertEq(token.totalSupply(), 0);

        // approve LP tokens for token contract and add them to contract
        pair.approve(address(token), addedLiq);
        token.addLP(addedLiq);
        assertEq(token.totalSupply(), addedLiq * 2);
        assertEq(pair.balanceOf(address(token)), addedLiq);
    }

    function test_Minting() public {
        test_Liquidity_Adding();

        assertEq(token.deviation(), 0);
        switchPrank(deployer);

        // mint tokens by owner and check if deviation has increased accordingly
        token.mint(userB, 1e5);
        assertEq(token.balanceOf(userB), 1e5);
        assertEq(token.deviation(), 1e5);
    }

    function test_Burning() public {
        test_Liquidity_Adding();

        assertEq(token.deviation(), 0);
        switchPrank(deployer);

        // issue some tokens for userB and burn them to check the deviation was decreased accordingly
        token.issue(userB, 1e5);
        token.burn(userB, 1e5);
        assertEq(token.deviation(), -1e5);
    }

    function test_Blacklist_Adding() public {
        test_Liquidity_Adding();
        switchPrank(deployer);
        token.issue(userB, 1e8);

        // check if user can transfer his tokens
        switchPrank(userB);
        token.transfer(userC, 1e7);
        assertEq(token.balanceOf(userC), 1e7);
        assertEq(token.balanceOf(userB), 9e7);

        // add to blacklist
        switchPrank(deployer);
        token.addToBlacklist(userB);
        assertTrue(token.hasRole(token.BLACKLISTED(), userB));

        // check if user cannot transfer tokens after blocking
        switchPrank(userB);
        vm.expectRevert(IPeggedAsset.Blacklisted.selector);
        token.transfer(userC, 1e7);
    }

    function test_Blacklist_Removing() public {
        test_Blacklist_Adding();

        switchPrank(deployer);
        token.removeFromBlacklist(userB);

        switchPrank(userB);
        token.transfer(userC, 1e7);
        assertEq(token.balanceOf(userC), 2e7);
        assertFalse(token.hasRole(token.BLACKLISTED(), userB));
    }

    function test_DeviationControl() public {
        test_Liquidity_Adding();

        switchPrank(deployer);
        token.issue(deployer, 1e8);
        token.setMaxDeviation(100);

        // reach max border of deviation
        token.mint(deployer, 100);

        // trying to cross the max border
        vm.expectRevert(IPeggedAsset.TooLargeDeviation.selector);
        token.mint(deployer, 1);

        // reach min border of deviation
        token.burn(deployer, 200);

        // trying to cross the min border
        vm.expectRevert(IPeggedAsset.TooLargeDeviation.selector);
        token.burn(deployer, 1);
    }

    function _deploy() public {
        switchPrank(deployer);

        tokenA = new MockTrackedToken("TokenA", "TKA");
        tokenB = new MockTrackedToken("TokenB", "TKB");

        factory = Deployer.deployFactory(deployer);
        // pair = IUniswapV2Pair(factory.createPair(address(tokenA), address(tokenB)));
        weth = Deployer.deployWETH();
        router = Deployer.deployRouterV2(address(factory), address(weth));

        implementation = new PeggedAsset();
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            deployer, // proxy owner
            ""
        );

        token = PeggedAsset(address(proxy));

        token.initialize(deployer, "Stablecoin", "STB", address(tokenA), address(tokenB), address(router), 6);

        tokenA.mint(userA, 100e18);
        tokenB.mint(userA, 100e18);

        token.setMaxDeviation(1000e6); // max deviation eq to 1000 usd

        switchPrank(userA);
        tokenA.approve(address(token), ~uint256(0));
        tokenB.approve(address(token), ~uint256(0));
        tokenA.approve(address(router), ~uint256(0));
        tokenB.approve(address(router), ~uint256(0));
    }

    function switchPrank(address user) internal {
        vm.stopPrank();
        vm.startPrank(user);
    }
}