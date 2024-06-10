// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockLpToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address who, uint256 amount) public {
        _mint(who, amount);
    }

    function burn(address who, uint256 amount) public {
        _burn(who, amount);
    }
}   