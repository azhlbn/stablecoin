// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import {Test, console} from "forge-std/Test.sol";
import {PeggedAsset} from "../src/PeggedAsset.sol";
import {MockLpToken} from "./mocs/MockLpToken.sol";

contract PeggedAssetTest is Test {
    ProxyAdmin admin;

    TransparentUpgradeableProxy proxy;
    PeggedAsset implementation;
    PeggedAsset token;

    MockLpToken lp;

    address user;
    address deployer;

    function setUp() public {
        deployer = vm.addr(1);
        user = vm.addr(2);

        _deploy();
    }

    function _deploy() internal {
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
}
