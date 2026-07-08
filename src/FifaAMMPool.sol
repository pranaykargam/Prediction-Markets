// SPDX-License-Identifier: MIT
pragma solidity ^0.5.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AMM pool for prediction market outcome tokens
/// @notice Handles liquidity, swaps, and winner payout using USDC / YES / NO.
contract AMMPool {
    address public market;
    IERC20 public immutable usdc;
    IERC20 public immutable yesToken;
    IERC20 public immutable noToken;
    uint16 public immutable feeBps;

    uint256 public lpTotalSupply;
    mapping(address => uint256) public lpShares;

    event MarketSet(address indexed market);
    event LiquidityAdded(address indexed provider, uint256 lpShares);
    event LiquidityRemoved(address indexed provider, uint256 usdcOut, uint256 yesOut, uint256 noOut);
    event Swap(address indexed senderToken, address indexed recipient, address indexed outputToken, uint256 amountIn, uint256 amountOut);
    event WinnerPaid(address indexed recipient, bool yesWinner, uint256 tokenAmount, uint256 usdcOut);

    modifier onlyMarket() {
        require(msg.sender == market, "AMMPool: only market");
        _;
    }

    constructor(
        address _usdc,
        address _yesToken,
        address _noToken,
        address _market,
        uint16 _feeBps
    ) {
        require(_usdc != address(0), "AMMPool: zero usdc");
        require(_yesToken != address(0), "AMMPool: zero yes token");
        require(_noToken != address(0), "AMMPool: zero no token");
        require(_feeBps < 10000, "AMMPool: invalid fee");

        usdc = IERC20(_usdc);
        yesToken = IERC20(_yesToken);
        noToken = IERC20(_noToken);
        market = _market;
        feeBps = _feeBps;
    }

    function setMarket(address _market) external {
        require(market == address(0), "AMMPool: market already set");
        require(_market != address(0), "AMMPool: zero market");
        market = _market;
        emit MarketSet(_market);
    }

    function addLiquidity(
        address provider,
        uint256 usdcAmount,
        uint256 yesAmount,
        uint256 noAmount
    ) external onlyMarket returns (uint256 shares) {
        require(usdcAmount > 0, "AMMPool: zero usdc");
        require(yesAmount > 0, "AMMPool: zero yes");
        require(noAmount > 0, "AMMPool: zero no");

        uint256 reserveUsdc = usdc.balanceOf(address(this)) - usdcAmount;
        uint256 reserveYes = yesToken.balanceOf(address(this)) - yesAmount;
        uint256 reserveNo = noToken.balanceOf(address(this)) - noAmount;

        if (lpTotalSupply == 0) {
            shares = usdcAmount;
        } else {
            uint256 shareUsdc = (usdcAmount * lpTotalSupply) / reserveUsdc;
            uint256 shareYes = (yesAmount * lpTotalSupply) / reserveYes;
            uint256 shareNo = (noAmount * lpTotalSupply) / reserveNo;
            shares = _min(_min(shareUsdc, shareYes), shareNo);
        }

        require(shares > 0, "AMMPool: zero shares");
        lpShares[provider] += shares;
        lpTotalSupply += shares;

        emit LiquidityAdded(provider, shares);
    }

    function removeLiquidity(address provider, uint256 shares)
        external
        onlyMarket
        returns (
            uint256 usdcOut,
            uint256 yesOut,
            uint256 noOut
        )
    {
        require(shares > 0, "AMMPool: zero shares");
        require(lpShares[provider] >= shares, "AMMPool: insufficient shares");

        uint256 currentUsdc = usdc.balanceOf(address(this));
        uint256 currentYes = yesToken.balanceOf(address(this));
        uint256 currentNo = noToken.balanceOf(address(this));

        usdcOut = (currentUsdc * shares) / lpTotalSupply;
        yesOut = (currentYes * shares) / lpTotalSupply;
        noOut = (currentNo * shares) / lpTotalSupply;

        lpShares[provider] -= shares;
        lpTotalSupply -= shares;

        require(usdc.transfer(provider, usdcOut), "AMMPool: usdc transfer failed");
        require(yesToken.transfer(provider, yesOut), "AMMPool: yes transfer failed");
        require(noToken.transfer(provider, noOut), "AMMPool: no transfer failed");

        emit LiquidityRemoved(provider, usdcOut, yesOut, noOut);
    }

    function swapUsdcForYes(
        uint256 usdcAmount,
        uint256 minYesOut,
        address recipient
    ) external onlyMarket returns (uint256 yesOut) {
        yesOut = _getAmountOut(
            usdcAmount,
            usdc.balanceOf(address(this)) - usdcAmount,
            yesToken.balanceOf(address(this))
        );
        require(yesOut >= minYesOut, "AMMPool: slippage yes");
        require(yesToken.transfer(recipient, yesOut), "AMMPool: yes transfer failed");

        emit Swap(address(usdc), recipient, address(yesToken), usdcAmount, yesOut);
    }

    function swapUsdcForNo(
        uint256 usdcAmount,
        uint256 minNoOut,
        address recipient
    ) external onlyMarket returns (uint256 noOut) {
        noOut = _getAmountOut(
            usdcAmount,
            usdc.balanceOf(address(this)) - usdcAmount,
            noToken.balanceOf(address(this))
        );
        require(noOut >= minNoOut, "AMMPool: slippage no");
        require(noToken.transfer(recipient, noOut), "AMMPool: no transfer failed");

        emit Swap(address(usdc), recipient, address(noToken), usdcAmount, noOut);
    }

    function swapYesForUsdc(
        uint256 yesAmount,
        uint256 minUsdcOut,
        address recipient
    ) external onlyMarket returns (uint256 usdcOut) {
        usdcOut = _getAmountOut(
            yesAmount,
            yesToken.balanceOf(address(this)) - yesAmount,
            usdc.balanceOf(address(this))
        );
        require(usdcOut >= minUsdcOut, "AMMPool: slippage usdc");
        require(usdc.transfer(recipient, usdcOut), "AMMPool: usdc transfer failed");

        emit Swap(address(yesToken), recipient, address(usdc), yesAmount, usdcOut);
    }

    function swapNoForUsdc(
        uint256 noAmount,
        uint256 minUsdcOut,
        address recipient
    ) external onlyMarket returns (uint256 usdcOut) {
        usdcOut = _getAmountOut(
            noAmount,
            noToken.balanceOf(address(this)) - noAmount,
            usdc.balanceOf(address(this))
        );
        require(usdcOut >= minUsdcOut, "AMMPool: slippage usdc");
        require(usdc.transfer(recipient, usdcOut), "AMMPool: usdc transfer failed");

        emit Swap(address(noToken), recipient, address(usdc), noAmount, usdcOut);
    }

    function payoutWinningTokens(
        bool yesWinner,
        uint256 tokenAmount,
        address recipient
    ) external onlyMarket {
        require(tokenAmount > 0, "AMMPool: zero amount");
        require(usdc.balanceOf(address(this)) >= tokenAmount, "AMMPool: insufficient usdc");
        require(usdc.transfer(recipient, tokenAmount), "AMMPool: payout failed");

        emit WinnerPaid(recipient, yesWinner, tokenAmount, tokenAmount);
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) private pure returns (uint256) {
        require(amountIn > 0, "AMMPool: zero input");
        require(reserveIn > 0 && reserveOut > 0, "AMMPool: empty reserves");
        uint256 amountInWithFee = amountIn * (10000 - feeBps);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10000 + amountInWithFee;
        return numerator / denominator;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}