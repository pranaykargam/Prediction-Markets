// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PredictionMarketToken} from "./PredictionMarketToken.sol";

contract PredictionMarket is Ownable {
    //////////////////////////
    /// Errors             ///
    //////////////////////////
    error PredictionMarket__MustProvideETHForInitialLiquidity();
    error PredictionMarket__InvalidProbability();
    error PredictionMarket__InvalidPercentageToLock();
    error PredictionMarket__InvalidInitialTokenValue();
    error PredictionMarket__TokenTransferFailed();

    uint256 private constant PRECISION = 1e18;

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
    PredictionMarketToken public immutable i_yesToken;
    PredictionMarketToken public immutable i_noToken;

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
        if (_initialTokenValue == 0) {
            revert PredictionMarket__InvalidInitialTokenValue();
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

        uint256 initialTokenAmount = (msg.value * PRECISION) / _initialTokenValue;

        // Mint initial supply to this market so it can lock and distribute.
        i_yesToken = new PredictionMarketToken("Yes", "Y", address(this), initialTokenAmount);
        i_noToken = new PredictionMarketToken("No", "N", address(this), initialTokenAmount);

        uint256 initialYesAmountLocked =
            (initialTokenAmount * _initialYesProbability * _percentageToLock * 2) / 10000;
        uint256 initialNoAmountLocked =
            (initialTokenAmount * (100 - _initialYesProbability) * _percentageToLock * 2) / 10000;

        bool success1 = i_yesToken.transfer(msg.sender, initialYesAmountLocked);
        bool success2 = i_noToken.transfer(msg.sender, initialNoAmountLocked);
        if (!success1 || !success2) {
            revert PredictionMarket__TokenTransferFailed();
        }
    }
}

