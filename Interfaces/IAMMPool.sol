// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Interface used by a prediction market to manage its outcome-token AMM.
interface IAMMPool {
    function addLiquidity(address provider, uint256 usdcAmount, uint256 yesAmount, uint256 noAmount)
        external
        returns (uint256 shares);

    function removeLiquidity(address provider, uint256 shares)
        external
        returns (uint256 usdcOut, uint256 yesOut, uint256 noOut);

    function swapUsdcForYes(uint256 usdcAmount, uint256 minYesOut, address recipient) external returns (uint256);
    function swapUsdcForNo(uint256 usdcAmount, uint256 minNoOut, address recipient) external returns (uint256);
    function swapYesForUsdc(uint256 yesAmount, uint256 minUsdcOut, address recipient) external returns (uint256);
    function swapNoForUsdc(uint256 noAmount, uint256 minUsdcOut, address recipient) external returns (uint256);
    function payoutWinningTokens(bool yesWinner, uint256 tokenAmount, address recipient) external;
}
