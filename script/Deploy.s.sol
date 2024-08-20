// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import {PeggedAsset} from "./../src/PeggedAsset.sol";

contract Deploy is Script {
    TransparentUpgradeableProxy proxy;
    PeggedAsset impl;
    PeggedAsset token;

    ProxyAdmin admin;

    IERC20 usdc;
    IERC20 usdt;
    
    address owner;

    function setUp() public {
        owner = 0x4E2Fb43df4857213D22acBFd54E147ea583Ae225;
        // owner = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;
        usdc = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    }

    function run() public {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPK);

        impl = new PeggedAsset();
        proxy = new TransparentUpgradeableProxy(
            address(impl),
            vm.addr(deployerPK),
            ""
        );
        token = PeggedAsset(address(proxy));

        token.initialize(
            owner, 
            "FUSDN",
            "FUSDN",
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // usdc
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // usdt
            0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24, // router
            6
        );

        usdc.approve(address(token), type(uint256).max);
        usdt.approve(address(token), type(uint256).max);
        // token.setMaxDeviation(1000e6);

        vm.stopBroadcast();

        console.log("Deployed proxy: ", address(proxy));
        console.log("Deployer admin: ", vm.addr(deployerPK));
        console.log("Deployed impl: ", address(impl));
    }
}

// with d owner
// == Logs ==
//   Deployed proxy:  0x9e364c26D3b470DCc6bB2210fAf45E9f38D40908
//   Deployer admin:  0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5
//   Deployed impl:  0xA82187BF382bcDf6A3d7518D7f3ed5a1b381F547