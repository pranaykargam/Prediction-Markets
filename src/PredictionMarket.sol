// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PredictionMarket is Ownable {
    //////////////////////////
    /// Errors             ///
    //////////////////////////
    error PredictionMarket__MustProvideETHForInitialLiquidity();
    error PredictionMarket__InvalidProbability();
    error PredictionMarket__InvalidPercentageToLock();

    //////////////////////////
    /// State Variables    ///
    //////////////////////////
    address public immutable i_oracle;
    uint256 public immutable i_initialTokenValue;
    uint256 public immutable i_percentageLocked;
    uint256 public immutable i_initialYesProbability;

    string public s_question;
    uint256 public s_ethCollateral;
    uint256 public s_lpTradingRevenue;

    //////////////////
    ////Constructor///
    //////////////////
    constructor(
        address _liquidityProvider,
        address _oracle,
        string memory _question,
        uint256 _initialTokenValue,
        uint8 _initialYesProbability,
        uint8 _percentageToLock
    ) payable Ownable(_liquidityProvider) {
        if (msg.value == 0) {
            revert PredictionMarket__MustProvideETHForInitialLiquidity();
        }
        if (_initialYesProbability >= 100 || _initialYesProbability == 0) {
            revert PredictionMarket__InvalidProbability();
        }
        if (_percentageToLock >= 100 || _percentageToLock == 0) {
            revert PredictionMarket__InvalidPercentageToLock();
        }

        i_oracle = _oracle;
        s_question = _question;
        i_initialTokenValue = _initialTokenValue;
        i_initialYesProbability = _initialYesProbability;
        i_percentageLocked = _percentageToLock;

        s_ethCollateral = msg.value;
    }
}

