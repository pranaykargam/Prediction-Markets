// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Interfaces/IOutcomeToken.sol";

/// @title Prediction market outcome token
/// @notice ERC20 YES / NO token minted and burned only by the market contract.
contract PredictionMarketToken is ERC20, IOutcomeToken {
    address public minter;

    event MinterUpdated(address indexed previousMinter, address indexed newMinter);

    modifier onlyMinter() {
        require(msg.sender == minter, "PredictionMarketToken: only minter");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address initialMinter_
    ) ERC20(name_, symbol_) {
        require(initialMinter_ != address(0), "PredictionMarketToken: zero minter");
        minter = initialMinter_;
        emit MinterUpdated(address(0), initialMinter_);
    }

    function setMinter(address newMinter) external onlyMinter {
        require(newMinter != address(0), "PredictionMarketToken: zero minter");
        emit MinterUpdated(minter, newMinter);
        minter = newMinter;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
