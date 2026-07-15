// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FifaAMMPool.sol";
import "./PredictionMarketToken.sol";
import "../Interfaces/IResultOracle.sol";
import "../Interfaces/IAMMPool.sol";

/// @title Prediction market contract
/// @notice Manages lifecycle, trading, oracle settlement, and redemption.
contract PredictionMarket is ReentrancyGuard {
    using SafeERC20 for IERC20;
    enum MarketState {
        OPEN,
        CLOSED,
        REPORTED,
        RESOLVED
    }

    IERC20 public immutable usdc;
    PredictionMarketToken public immutable yesToken;
    PredictionMarketToken public immutable noToken;
    IAMMPool public immutable pool;
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
        require(state == MarketState.OPEN && block.timestamp < kickoffTime, "PredictionMarket: market not open");
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
        pool = IAMMPool(poolAddress);
        resultOracle = IResultOracle(oracleAddress);

        matchId = _matchId;
        home = _home;
        away = _away;
        kickoffTime = _kickoffTime;
        state = MarketState.OPEN;
    }

    function buyYesWithUsdc(uint256 usdcAmount, uint256 minYesOut) external nonReentrant onlyWhenOpen {
        require(usdcAmount > 0, "PredictionMarket: zero amount");
        usdc.safeTransferFrom(msg.sender, address(pool), usdcAmount);
        pool.swapUsdcForYes(usdcAmount, minYesOut, msg.sender);
    }

    function buyNoWithUsdc(uint256 usdcAmount, uint256 minNoOut) external nonReentrant onlyWhenOpen {
        require(usdcAmount > 0, "PredictionMarket: zero amount");
        usdc.safeTransferFrom(msg.sender, address(pool), usdcAmount);
        pool.swapUsdcForNo(usdcAmount, minNoOut, msg.sender);
    }

    function sellYesForUsdc(uint256 yesAmount, uint256 minUsdcOut) external nonReentrant onlyWhenOpen {
        require(yesAmount > 0, "PredictionMarket: zero amount");
        IERC20(address(yesToken)).safeTransferFrom(msg.sender, address(pool), yesAmount);
        pool.swapYesForUsdc(yesAmount, minUsdcOut, msg.sender);
    }

    function sellNoForUsdc(uint256 noAmount, uint256 minUsdcOut) external nonReentrant onlyWhenOpen {
        require(noAmount > 0, "PredictionMarket: zero amount");
        IERC20(address(noToken)).safeTransferFrom(msg.sender, address(pool), noAmount);
        pool.swapNoForUsdc(noAmount, minUsdcOut, msg.sender);
    }

    function addLiquidity(
        uint256 usdcAmount,
        uint256 yesAmount,
        uint256 noAmount
    ) external nonReentrant onlyWhenOpen {
        require(usdcAmount > 0 && yesAmount > 0, "PredictionMarket: zero liquidity");
        require(yesAmount == noAmount, "PredictionMarket: unmatched outcomes");
        require(usdcAmount >= yesAmount, "PredictionMarket: insufficient collateral");
        usdc.safeTransferFrom(msg.sender, address(pool), usdcAmount);
        yesToken.mint(address(pool), yesAmount);
        noToken.mint(address(pool), noAmount);
        pool.addLiquidity(msg.sender, usdcAmount, yesAmount, noAmount);

        emit LiquidityAdded(msg.sender, usdcAmount, yesAmount, noAmount);
    }

    function removeLiquidity(uint256 lpShares) external nonReentrant onlyWhenOpen {
        require(lpShares > 0, "PredictionMarket: zero shares");
        pool.removeLiquidity(msg.sender, lpShares);
        emit LiquidityRemoved(msg.sender, lpShares);
    }

    function closeMarket() external {
        require(state == MarketState.OPEN, "PredictionMarket: not open");
        require(block.timestamp >= kickoffTime, "PredictionMarket: kickoff not reached");
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

    function redeemWinningTokens(uint256 amount) external nonReentrant onlyAfterReport {
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
