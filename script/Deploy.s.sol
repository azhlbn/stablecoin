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
    
    address owner;

    function setUp() public {
        owner = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;
    }

    function run() public {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPK);

        admin = new ProxyAdmin(owner);

        impl = new PeggedAsset();
        proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(admin),
            ""
        );
        token = PeggedAsset(address(proxy));

        token.initialize(
            IERC20(0xf41Aa588fB744a3569F2c378aF58Ac03Db6f534e),
            owner, 
            "Pegged Asset",
            "PGA"
        );

        vm.stopBroadcast();

        console.log("Deployed proxy: ", address(proxy));
        console.log("Deployed impl: ", address(impl));
    }
}

// == Logs ==
//   Deployed proxy:  0x08243595e33F0aeC1Ce8d1d4CEDf25957ab6F694
//   Deployed impl:  0xA758433d1Ed6a83567D371eeE9ff1137CDef8cf9

// forge verify-contract \
//     --chain-id 11155111 \
//     --num-of-optimizations 1000000 \
//     --watch \
//     --etherscan-api-key "AXQETH55UUJXDQJ13H59IYHYAZYWB2XBIG" \
//     --compiler-version v0.8.24+commit.e11b9ed9 \
//     0xA758433d1Ed6a83567D371eeE9ff1137CDef8cf9 \
//     src/PeggedAsset.sol:PeggedAsset

// forge create --rpc-url sepolia \
//     --private-key "0xb645aaa13090fcd42d8d98921229217e6cb9f4e4c06181b01b9d43d1e2f60fbd" \
//     --etherscan-api-key "AXQETH55UUJXDQJ13H59IYHYAZYWB2XBIG" \
//     --verify \
//     src/PeggedAsset.sol:PeggedAsset