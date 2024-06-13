// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPK);

        

        console.log("Deployed at:", address(xnastr));

        vm.stopBroadcast();
    }
}
