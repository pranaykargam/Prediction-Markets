// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";

contract PredictionMarketTest is Test {
    PredictionMarket internal market;
    address internal owner = makeAddr("owner");
    address internal oracle = makeAddr("oracle");

    receive() external payable {}

    function setUp() public {
        vm.deal(owner, 100 ether);

        vm.prank(owner);
        market = new PredictionMarket{value: 1 ether}(
            owner,
            oracle,
            "Will it rain?",
            1e18,
            50, // 50% YES
            10 // 10% lock
        );
    }

    function test_resolveMarketAndWithdraw_sendsEthToOwner() public {
        uint256 ownerBefore = owner.balance;

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        vm.prank(owner);
        uint256 ethRedeemed = market.resolveMarketAndWithdraw();

        // 1 ETH deposit, 1e18 token supply; 10% of YES supply locked to LP => 0.9e18 YES left in market.
        // ethRedeemed = 0.9e18 * 1e18 / 1e18 = 0.9 ETH; s_ethCollateral goes 1 ETH -> 0.1 ETH.
        assertEq(ethRedeemed, 0.9 ether);
        assertEq(market.s_ethCollateral(), 0.1 ether);

        uint256 ownerAfter = owner.balance;
        assertEq(ownerAfter - ownerBefore, 0.9 ether, "owner receives redeemed collateral (no trading revenue here)");
    }

    function test_resolveMarketAndWithdraw_revertsIfNotReported() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__PredictionNotReported.selector);
        market.resolveMarketAndWithdraw();
    }

    /// @dev Name starts with `test_report` so `forge test --match-test test_report` matches.
    function test_report_onlyOracleCanReport() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__OnlyOracleCanReport.selector);
        market.report(PredictionMarket.Outcome.YES);

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);
        assertTrue(market.s_isReported());
        assertEq(address(market.s_winningToken()), address(market.i_yesToken()));
    }

    /// @dev Name contains `removeLiquidity` so `forge test --match-test removeLiquidity` matches.
    function test_removeLiquidity_withdrawsEth() public {
        uint256 beforeBal = owner.balance;

        vm.prank(owner);
        market.removeLiquidity(0.1 ether);

        assertEq(market.s_ethCollateral(), 0.9 ether);
        assertEq(owner.balance, beforeBal + 0.1 ether);
    }

    function test_redeemWinningTokens() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        uint256 tokensToBuy = 0.5 ether; // 0.5e18 tokens
        uint256 ethNeeded = market.getBuyPriceInEth(PredictionMarket.Outcome.YES, tokensToBuy);

        // User buys YES tokens
        vm.prank(user);
        market.buyTokensWithETH{value: ethNeeded}(PredictionMarket.Outcome.YES, tokensToBuy);

        // Oracle reports YES as winner
        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        uint256 userBalanceBefore = user.balance;
        uint256 winningTokensBefore = market.i_yesToken().balanceOf(user);

        // User redeems winning tokens
        vm.prank(user);
        market.redeemWinningTokens(winningTokensBefore);

        uint256 ethReceived = (winningTokensBefore * 1e18) / 1e18; // initialTokenValue is 1e18, PRECISION is 1e18
        assertEq(user.balance, userBalanceBefore + ethReceived);
        assertEq(market.i_yesToken().balanceOf(user), 0);
        assertEq(market.s_ethCollateral(), 1 ether - ethReceived); // initial 1 ether minus redeemed
    }
}
