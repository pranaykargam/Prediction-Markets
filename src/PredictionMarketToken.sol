// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PredictionMarketToken is ERC20 {
    constructor(string memory name, string memory symbol, address initialOwner, uint256 initialSupply)
        ERC20(name, symbol)
    {
        _mint(initialOwner, initialSupply);
    }
}

