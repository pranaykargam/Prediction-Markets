// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PredictionMarketToken} from "./PredictionMarketToken.sol";

contract PredictionMarket is Ownable {
    //////////////////////////
    /// Types              ///
    //////////////////////////
    enum Outcome {
        YES,
        NO
    }

    //////////////////////////
    /// Errors             ///
    //////////////////////////
    error PredictionMarket__MustProvideETHForInitialLiquidity();
    error PredictionMarket__InvalidProbability();
    error PredictionMarket__InvalidPercentageToLock();
    error PredictionMarket__InvalidInitialTokenValue();
    error PredictionMarket__TokenTransferFailed();
    error PredictionMarket__InsufficientTokenReserve(Outcome outcome, uint256 requested);
    error PredictionMarket__ETHTransferFailed();
    error PredictionMarket__InsufficientETHCollateral();
    error PredictionMarket__PredictionAlreadyReported();
    error PredictionMarket__PredictionNotReported();
    error PredictionMarket__OnlyOracleCanReport();
    error PredictionMarket__InsufficientLiquidity();
    error PredictionMarket__MustSendExactETHAmount();
    error PredictionMarket__InsufficientBalance(uint256 requested, uint256 actual);
    error PredictionMarket__InsufficientAllowance(uint256 requested, uint256 actual);
    error PredictionMarket__OwnerCannotCall();
    error PredictionMarket__AmountMustBeGreaterThanZero();
    error PredictionMarket__InsufficientWinningTokens();

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
    PredictionMarketToken public s_winningToken;
    bool public s_isReported;
    PredictionMarketToken public immutable i_yesToken;
    PredictionMarketToken public immutable i_noToken;

    //////////////////////////
    /// Events             ///
    //////////////////////////
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokensAmount);
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 tokensBurned);
    event MarketReported(address indexed oracle, Outcome winningOutcome, address winningToken);
    event MarketResolved(address indexed owner, uint256 totalEthSent);

    event TokensPurchased(
        address indexed buyer,
        uint256 indexed outcome,
        uint256 amountTokenToBuy,
        uint256 ethSpent
    );

    event TokensSold(
        address indexed seller,
        uint256 indexed outcome,
        uint256 amountTokenSold,
        uint256 ethReceived
    );

      event WinningTokensRedeemed(
        address indexed redeemer,
        uint256 amountTokensRedeemed,
        uint256 ethReceived
    );

    ///////////////////
    /// Modifiers    ///
    ///////////////////
    modifier predictionNotReported() {
        if (s_isReported) {
            revert PredictionMarket__PredictionAlreadyReported();
        }
        _;
    }

    modifier predictionReported() {
        if (!s_isReported) {
            revert PredictionMarket__PredictionNotReported();
        }
        _;
    }

    modifier notOwner() {
        if (msg.sender == owner()) {
            revert PredictionMarket__OwnerCannotCall();
        }
        _;
    }

    modifier amountGreaterThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert PredictionMarket__AmountMustBeGreaterThanZero();
        }
        _;
    }

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

    ///////////////////
    /// Functions     ///
    ///////////////////

    function addLiquidity() external payable onlyOwner predictionNotReported {
        s_ethCollateral += msg.value;

        uint256 tokensAmount = (msg.value * PRECISION) / i_initialTokenValue;

        i_yesToken.mint(address(this), tokensAmount);
        i_noToken.mint(address(this), tokensAmount);

        emit LiquidityAdded(msg.sender, msg.value, tokensAmount);
    }

    function removeLiquidity(uint256 _ethToWithdraw) external onlyOwner predictionNotReported {
        if (_ethToWithdraw > s_ethCollateral) {
            revert PredictionMarket__InsufficientETHCollateral();
        }

        uint256 amountTokenToBurn = (_ethToWithdraw * PRECISION) / i_initialTokenValue;

        if (amountTokenToBurn > i_yesToken.balanceOf(address(this))) {
            revert PredictionMarket__InsufficientTokenReserve(Outcome.YES, amountTokenToBurn);
        }

        if (amountTokenToBurn > i_noToken.balanceOf(address(this))) {
            revert PredictionMarket__InsufficientTokenReserve(Outcome.NO, amountTokenToBurn);
        }

        s_ethCollateral -= _ethToWithdraw;

        i_yesToken.burn(address(this), amountTokenToBurn);
        i_noToken.burn(address(this), amountTokenToBurn);

        (bool success,) = msg.sender.call{value: _ethToWithdraw}("");
        if (!success) {
            revert PredictionMarket__ETHTransferFailed();
        }

        emit LiquidityRemoved(msg.sender, _ethToWithdraw, amountTokenToBurn);
    }

    function report(Outcome _winningOutcome) external predictionNotReported {
        if (msg.sender != i_oracle) {
            revert PredictionMarket__OnlyOracleCanReport();
        }

        s_winningToken = _winningOutcome == Outcome.YES ? i_yesToken : i_noToken;
        s_isReported = true;

        emit MarketReported(msg.sender, _winningOutcome, address(s_winningToken));
    }

    function resolveMarketAndWithdraw()
        external
        onlyOwner
        predictionReported
        returns (uint256 ethRedeemed)
    {
        uint256 contractWinningTokens = s_winningToken.balanceOf(address(this));
        if (contractWinningTokens > 0) {
            ethRedeemed = (contractWinningTokens * i_initialTokenValue) / PRECISION;

            if (ethRedeemed > s_ethCollateral) {
                ethRedeemed = s_ethCollateral;
            }

            s_ethCollateral -= ethRedeemed;
        }

        uint256 totalEthToSend = ethRedeemed + s_lpTradingRevenue;

        s_lpTradingRevenue = 0;

        if (contractWinningTokens > 0) {
            s_winningToken.burn(address(this), contractWinningTokens);
        }

        (bool success,) = msg.sender.call{value: totalEthToSend}("");
        if (!success) {
            revert PredictionMarket__ETHTransferFailed();
        }

        emit MarketResolved(msg.sender, totalEthToSend);

        return ethRedeemed;
    }

    function getBuyPriceInEth(Outcome _outcome, uint256 _tradingAmount)
        public
        view
        returns (uint256)
    {
        return _calculatePriceInEth(_outcome, _tradingAmount, false);
    }

    function getSellPriceInEth(Outcome _outcome, uint256 _tradingAmount)
        public
        view
        returns (uint256)
    {
        return _calculatePriceInEth(_outcome, _tradingAmount, true);
    }

    // Helper Functions

    function _calculatePriceInEth(Outcome _outcome, uint256 _tradingAmount, bool _isSelling)
        private
        view
        returns (uint256)
    {
        (uint256 currentTokenReserve, uint256 currentOtherTokenReserve) = _getCurrentReserves(_outcome);

        // Ensure sufficient liquidity when buying
        if (!_isSelling) {
            if (currentTokenReserve < _tradingAmount) {
                revert PredictionMarket__InsufficientLiquidity();
            }
        }

        uint256 totalTokenSupply = i_yesToken.totalSupply();

        // Before trade
        uint256 currentTokenSoldBefore = totalTokenSupply - currentTokenReserve;
        uint256 currentOtherTokenSold = totalTokenSupply - currentOtherTokenReserve;

        uint256 totalTokensSoldBefore = currentTokenSoldBefore + currentOtherTokenSold;
        uint256 probabilityBefore =
            _calculateProbability(currentTokenSoldBefore, totalTokensSoldBefore);

        // After trade
        uint256 currentTokenReserveAfter =
            _isSelling ? currentTokenReserve + _tradingAmount : currentTokenReserve - _tradingAmount;
        uint256 currentTokenSoldAfter = totalTokenSupply - currentTokenReserveAfter;

        uint256 totalTokensSoldAfter =
            _isSelling ? totalTokensSoldBefore - _tradingAmount : totalTokensSoldBefore + _tradingAmount;

        uint256 probabilityAfter =
            _calculateProbability(currentTokenSoldAfter, totalTokensSoldAfter);

        // Compute final price
        uint256 probabilityAvg = (probabilityBefore + probabilityAfter) / 2;
        return (i_initialTokenValue * probabilityAvg * _tradingAmount) / (PRECISION * PRECISION);
    }

    function _getCurrentReserves(Outcome _outcome) private view returns (uint256, uint256) {
        if (_outcome == Outcome.YES) {
            return (i_yesToken.balanceOf(address(this)), i_noToken.balanceOf(address(this)));
        } else {
            return (i_noToken.balanceOf(address(this)), i_yesToken.balanceOf(address(this)));
        }
    }

    function _calculateProbability(uint256 tokensSold, uint256 totalSold)
        private
        pure
        returns (uint256)
    {
        return (tokensSold * PRECISION) / totalSold;
    }

    function buyTokensWithETH(Outcome _outcome, uint256 _amountTokenToBuy)
        external
        payable
        amountGreaterThanZero(_amountTokenToBuy)
        predictionNotReported
        notOwner
    {
        // Checkpoint 8
        uint256 ethNeeded = getBuyPriceInEth(_outcome, _amountTokenToBuy);
        if (msg.value != ethNeeded) {
            revert PredictionMarket__MustSendExactETHAmount();
        }

        PredictionMarketToken optionToken =
            _outcome == Outcome.YES ? i_yesToken : i_noToken;

        if (_amountTokenToBuy > optionToken.balanceOf(address(this))) {
            revert PredictionMarket__InsufficientTokenReserve(_outcome, _amountTokenToBuy);
        }

        s_lpTradingRevenue += msg.value;

        bool success = optionToken.transfer(msg.sender, _amountTokenToBuy);
        if (!success) {
            revert PredictionMarket__TokenTransferFailed();
        }

        emit TokensPurchased(msg.sender, uint256(_outcome), _amountTokenToBuy, msg.value);
    }

    function sellTokensForEth(Outcome _outcome, uint256 _tradingAmount)
        external
        amountGreaterThanZero(_tradingAmount)
        predictionNotReported
        notOwner
    {
        
        PredictionMarketToken optionToken =
            _outcome == Outcome.YES ? i_yesToken : i_noToken;

        uint256 userBalance = optionToken.balanceOf(msg.sender);
        if (userBalance < _tradingAmount) {
            revert PredictionMarket__InsufficientBalance(_tradingAmount, userBalance);
        }

        uint256 allowance = optionToken.allowance(msg.sender, address(this));
        if (allowance < _tradingAmount) {
            revert PredictionMarket__InsufficientAllowance(_tradingAmount, allowance);
        }

        uint256 ethToReceive = getSellPriceInEth(_outcome, _tradingAmount);

        s_lpTradingRevenue -= ethToReceive;

        (bool sent,) = msg.sender.call{value: ethToReceive}("");
        if (!sent) {
            revert PredictionMarket__ETHTransferFailed();
        }

        bool success = optionToken.transferFrom(msg.sender, address(this), _tradingAmount);
        if (!success) {
            revert PredictionMarket__TokenTransferFailed();
        }

        emit TokensSold(msg.sender, uint256(_outcome), _tradingAmount, ethToReceive);
    }

    function redeemWinningTokens(uint256 _amount) external amountGreaterThanZero(_amount) predictionReported notOwner {
    /// Checkpoint 9 ////
    if (s_winningToken.balanceOf(msg.sender) < _amount) {
        revert PredictionMarket__InsufficientWinningTokens();
    }

    uint256 ethToReceive = (_amount * i_initialTokenValue) / PRECISION;

    s_ethCollateral -= ethToReceive;

    s_winningToken.burn(msg.sender, _amount);

    (bool success,) = msg.sender.call{value: ethToReceive}("");
    if (!success) {
        revert PredictionMarket__ETHTransferFailed();
    }

    emit WinningTokensRedeemed(msg.sender, _amount, ethToReceive);
}
}