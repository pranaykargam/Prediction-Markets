// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../core/AMMPool.sol";
import "../core/PredictionMarketToken.sol";
import "../oracle/IResultOracle.sol";

/// @title Prediction market contract
/// @notice Manages lifecycle, trading, oracle settlement, and redemption.
contract PredictionMarket {
    enum MarketState {
        OPEN,
        CLOSED,
        REPORTED,
        RESOLVED
    }

    IERC20 public immutable usdc;
    PredictionMarketToken public immutable yesToken;
    PredictionMarketToken public immutable noToken;
    AMMPool public immutable pool;
    IResultOracle public immutable resultOracle;

    uint256 public immutable matchId;
    string public home;
    string public away;
    uint64 public kickoffTime;

    MarketState public state;
    uint8 public winningOutcome;

    event MarketClosed(uint64 kickoffTime);
    event OutcomeReported(uint256 indexed matchId, uint8 outcome);
    event Redeemed(address indexed user, uint256 amount, uint8 outcome);
    event LiquidityAdded(address indexed provider, uint256 usdcAmount, uint256 yesAmount, uint256 noAmount);
    event LiquidityRemoved(address indexed provider, uint256 lpShares);

    modifier onlyOracle() {
        require(msg.sender == address(resultOracle), "PredictionMarket: only oracle");
        _;
    }

    modifier onlyWhenOpen() {
        require(state == MarketState.OPEN, "PredictionMarket: market not open");
        _;
    }

    modifier onlyAfterReport() {
        require(
            state == MarketState.REPORTED || state == MarketState.RESOLVED,
            "PredictionMarket: not settled"
        );
        _;
    }

    constructor(
        address usdcAddress,
        address yesTokenAddress,
        address noTokenAddress,
        address poolAddress,
        address oracleAddress,
        uint256 _matchId,
        string memory _home,
        string memory _away,
        uint64 _kickoffTime
    ) {
        require(usdcAddress != address(0), "PredictionMarket: zero usdc");
        require(yesTokenAddress != address(0), "PredictionMarket: zero yes token");
        require(noTokenAddress != address(0), "PredictionMarket: zero no token");
        require(poolAddress != address(0), "PredictionMarket: zero pool");
        require(oracleAddress != address(0), "PredictionMarket: zero oracle");
        require(_kickoffTime > block.timestamp, "PredictionMarket: kickoff must be future");

        usdc = IERC20(usdcAddress);
        yesToken = PredictionMarketToken(yesTokenAddress);
        noToken = PredictionMarketToken(noTokenAddress);
        pool = AMMPool(poolAddress);
        resultOracle = IResultOracle(oracleAddress);

        matchId = _matchId;
        home = _home;
        away = _away;
        kickoffTime = _kickoffTime;
        state = MarketState.OPEN;
    }

    function buyYesWithUsdc(uint256 usdcAmount, uint256 minYesOut) external onlyWhenOpen {
        require(usdc.transferFrom(msg.sender, address(pool), usdcAmount), "PredictionMarket: usdc transfer failed");
        pool.swapUsdcForYes(usdcAmount, minYesOut, msg.sender);
    }

    function buyNoWithUsdc(uint256 usdcAmount, uint256 minNoOut) external onlyWhenOpen {
        require(usdc.transferFrom(msg.sender, address(pool), usdcAmount), "PredictionMarket: usdc transfer failed");
        pool.swapUsdcForNo(usdcAmount, minNoOut, msg.sender);
    }

    function sellYesForUsdc(uint256 yesAmount, uint256 minUsdcOut) external onlyWhenOpen {
        require(yesToken.transferFrom(msg.sender, address(pool), yesAmount), "PredictionMarket: yes transfer failed");
        pool.swapYesForUsdc(yesAmount, minUsdcOut, msg.sender);
    }

    function sellNoForUsdc(uint256 noAmount, uint256 minUsdcOut) external onlyWhenOpen {
        require(noToken.transferFrom(msg.sender, address(pool), noAmount), "PredictionMarket: no transfer failed");
        pool.swapNoForUsdc(noAmount, minUsdcOut, msg.sender);
    }

    function addLiquidity(
        uint256 usdcAmount,
        uint256 yesAmount,
        uint256 noAmount
    ) external onlyWhenOpen {
        require(usdc.transferFrom(msg.sender, address(pool), usdcAmount), "PredictionMarket: usdc transfer failed");
        yesToken.mint(address(pool), yesAmount);
        noToken.mint(address(pool), noAmount);
        pool.addLiquidity(msg.sender, usdcAmount, yesAmount, noAmount);

        emit LiquidityAdded(msg.sender, usdcAmount, yesAmount, noAmount);
    }

    function removeLiquidity(uint256 lpShares) external {
        require(lpShares > 0, "PredictionMarket: zero shares");
        pool.removeLiquidity(msg.sender, lpShares);
        emit LiquidityRemoved(msg.sender, lpShares);
    }

    function closeMarket() external {
        require(state == MarketState.OPEN, "PredictionMarket: not open");
        require(block.timestamp < kickoffTime, "PredictionMarket: kickoff passed");
        state = MarketState.CLOSED;
        emit MarketClosed(kickoffTime);
    }

    function reportOutcome(uint8 outcome) external onlyOracle {
        require(state == MarketState.CLOSED, "PredictionMarket: market must be closed");
        require(outcome == 0 || outcome == 1, "PredictionMarket: invalid outcome");
        winningOutcome = outcome;
        state = MarketState.REPORTED;
        emit OutcomeReported(matchId, outcome);
    }

    function redeemWinningTokens(uint256 amount) external onlyAfterReport {
        require(amount > 0, "PredictionMarket: zero amount");

        if (winningOutcome == 1) {
            yesToken.burn(msg.sender, amount);
        } else {
            noToken.burn(msg.sender, amount);
        }

        pool.payoutWinningTokens(winningOutcome == 1, amount, msg.sender);
        emit Redeemed(msg.sender, amount, winningOutcome);
    }
}