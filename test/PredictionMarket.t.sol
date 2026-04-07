// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";

contract PredictionMarketTest is Test {
    PredictionMarket internal market;

    address internal owner = makeAddr("owner");
    address internal oracle = makeAddr("oracle");
    address internal user = makeAddr("user");
    address internal userTwo = makeAddr("userTwo");

    uint256 internal constant INITIAL_LIQUIDITY = 1 ether;
    uint256 internal constant INITIAL_TOKEN_VALUE = 1e18;
    uint8 internal constant INITIAL_YES_PROBABILITY = 50;
    uint8 internal constant INITIAL_LOCK_PERCENTAGE = 10;
    uint256 internal constant INITIAL_LOCKED_TOKENS = 0.1 ether;
    uint256 internal constant INITIAL_MARKET_RESERVE = 0.9 ether;

    receive() external payable {}

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(userTwo, 100 ether);

        market = _deployMarket(
            INITIAL_LIQUIDITY, INITIAL_TOKEN_VALUE, INITIAL_YES_PROBABILITY, INITIAL_LOCK_PERCENTAGE
        );
    }

    // Verifies deployment initializes owner/oracle config, token addresses, reserves, and LP seed balances.
    function test_constructor_setsInitialState() public view {
        assertEq(market.owner(), owner);
        assertEq(market.i_oracle(), oracle);
        assertEq(market.s_question(), "Will it rain?");
        assertEq(market.i_initialTokenValue(), INITIAL_TOKEN_VALUE);
        assertEq(market.i_initialYesProbability(), INITIAL_YES_PROBABILITY);
        assertEq(market.i_percentageLocked(), INITIAL_LOCK_PERCENTAGE);
        assertEq(market.s_ethCollateral(), INITIAL_LIQUIDITY);
        assertEq(market.i_yesToken().balanceOf(owner), INITIAL_LOCKED_TOKENS);
        assertEq(market.i_noToken().balanceOf(owner), INITIAL_LOCKED_TOKENS);
        assertEq(market.i_yesToken().balanceOf(address(market)), INITIAL_MARKET_RESERVE);
        assertEq(market.i_noToken().balanceOf(address(market)), INITIAL_MARKET_RESERVE);
    }

    // Verifies deployment reverts when no initial ETH liquidity is supplied.
    function test_constructor_revertsWithoutInitialLiquidity() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__MustProvideETHForInitialLiquidity.selector);
        new PredictionMarket{value: 0}(
            owner, oracle, "Will it rain?", INITIAL_TOKEN_VALUE, INITIAL_YES_PROBABILITY, INITIAL_LOCK_PERCENTAGE
        );
    }

    // Verifies deployment reverts when the token redemption value is zero.
    function test_constructor_revertsWithZeroInitialTokenValue() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidInitialTokenValue.selector);
        new PredictionMarket{value: INITIAL_LIQUIDITY}(
            owner, oracle, "Will it rain?", 0, INITIAL_YES_PROBABILITY, INITIAL_LOCK_PERCENTAGE
        );
    }

    // Verifies deployment reverts when the starting YES probability is 0 or 100.
    function test_constructor_revertsWithInvalidProbability() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidProbability.selector);
        new PredictionMarket{value: INITIAL_LIQUIDITY}(
            owner, oracle, "Will it rain?", INITIAL_TOKEN_VALUE, 0, INITIAL_LOCK_PERCENTAGE
        );

        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidProbability.selector);
        new PredictionMarket{value: INITIAL_LIQUIDITY}(
            owner, oracle, "Will it rain?", INITIAL_TOKEN_VALUE, 100, INITIAL_LOCK_PERCENTAGE
        );
    }

    // Verifies deployment reverts when the LP lock percentage is 0 or 100.
    function test_constructor_revertsWithInvalidPercentageToLock() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidPercentageToLock.selector);
        new PredictionMarket{value: INITIAL_LIQUIDITY}(
            owner, oracle, "Will it rain?", INITIAL_TOKEN_VALUE, INITIAL_YES_PROBABILITY, 0
        );

        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidPercentageToLock.selector);
        new PredictionMarket{value: INITIAL_LIQUIDITY}(
            owner, oracle, "Will it rain?", INITIAL_TOKEN_VALUE, INITIAL_YES_PROBABILITY, 100
        );
    }

    // Verifies adding liquidity increases collateral and mints matching YES/NO reserves into the market.
    function test_addLiquidity_updatesCollateralAndReserves() public {
        vm.prank(owner);
        market.addLiquidity{value: 0.4 ether}();

        assertEq(market.s_ethCollateral(), 1.4 ether);
        assertEq(market.i_yesToken().balanceOf(address(market)), 1.3 ether);
        assertEq(market.i_noToken().balanceOf(address(market)), 1.3 ether);
    }

    // Verifies liquidity operations are blocked once the market outcome has been reported.
    function test_addLiquidity_revertsAfterReport() public {
        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__PredictionAlreadyReported.selector);
        market.addLiquidity{value: 0.1 ether}();
    }

    // Verifies the owner can remove liquidity and the contract burns the paired reserve tokens.
    function test_removeLiquidity_withdrawsEthAndBurnsTokens() public {
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        market.removeLiquidity(0.1 ether);

        assertEq(market.s_ethCollateral(), 0.9 ether);
        assertEq(market.i_yesToken().balanceOf(address(market)), 0.8 ether);
        assertEq(market.i_noToken().balanceOf(address(market)), 0.8 ether);
        assertEq(owner.balance, ownerBalanceBefore + 0.1 ether);
    }

    // Verifies removal fails when the owner asks for more ETH than the market still collateralizes.
    function test_removeLiquidity_revertsWhenEthExceedsCollateral() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__InsufficientETHCollateral.selector);
        market.removeLiquidity(1.1 ether);
    }

    // Verifies removal fails if earlier trades drained one side below the burn amount required for withdrawal.
    function test_removeLiquidity_revertsWhenYesReserveIsTooLow() public {
        _buyTokens(user, PredictionMarket.Outcome.YES, 0.85 ether);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket.PredictionMarket__InsufficientTokenReserve.selector,
                PredictionMarket.Outcome.YES,
                0.1 ether
            )
        );
        market.removeLiquidity(0.1 ether);
    }

    // Verifies only the oracle can report and a successful report stores the winning token.
    function test_report_onlyOracleCanReport() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__OnlyOracleCanReport.selector);
        market.report(PredictionMarket.Outcome.YES);

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        assertTrue(market.s_isReported());
        assertEq(address(market.s_winningToken()), address(market.i_yesToken()));
    }

    // Verifies the market cannot be reported twice.
    function test_report_revertsWhenCalledTwice() public {
        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.NO);

        vm.prank(oracle);
        vm.expectRevert(PredictionMarket.PredictionMarket__PredictionAlreadyReported.selector);
        market.report(PredictionMarket.Outcome.YES);
    }

    // Verifies the buy helper returns the expected price for the initial 0.1 token YES purchase.
    function test_getBuyPriceInEth_returnsExpectedPrice() public view {
        uint256 price = market.getBuyPriceInEth(PredictionMarket.Outcome.YES, 0.1 ether);
        assertEq(price, 0.058333333333333333 ether);
    }

    // Verifies the sell helper returns the expected price after the user first buys tokens and moves the odds.
    function test_getSellPriceInEth_returnsExpectedPriceAfterBuy() public {
        _buyTokens(user, PredictionMarket.Outcome.YES, 0.1 ether);

        uint256 sellPrice = market.getSellPriceInEth(PredictionMarket.Outcome.YES, 0.1 ether);
        assertEq(sellPrice, 0.058333333333333333 ether);
    }

    // Verifies buying tokens transfers the correct outcome tokens to the trader and records LP trading revenue.
    function test_buyTokensWithETH_updatesBalancesAndRevenue() public {
        uint256 amountToBuy = 0.2 ether;
        uint256 ethNeeded = market.getBuyPriceInEth(PredictionMarket.Outcome.YES, amountToBuy);

        vm.prank(user);
        market.buyTokensWithETH{value: ethNeeded}(PredictionMarket.Outcome.YES, amountToBuy);

        assertEq(market.i_yesToken().balanceOf(user), amountToBuy);
        assertEq(market.i_yesToken().balanceOf(address(market)), 0.7 ether);
        assertEq(market.s_lpTradingRevenue(), ethNeeded);
    }

    // Verifies buying reverts when the caller sends the wrong ETH amount for the quoted trade.
    function test_buyTokensWithETH_revertsWhenEthAmountIsWrong() public {
        vm.prank(user); 
        vm.expectRevert(PredictionMarket.PredictionMarket__MustSendExactETHAmount.selector);
        market.buyTokensWithETH{value: 1 wei}(PredictionMarket.Outcome.YES, 0.1 ether);
    }

    // Verifies the owner cannot trade in their own market and zero-amount buys are rejected.
    function test_buyTokensWithETH_revertsForOwnerAndZeroAmount() public {
        uint256 ownerQuote = market.getBuyPriceInEth(PredictionMarket.Outcome.YES, 0.1 ether);

        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__OwnerCannotCall.selector);
        market.buyTokensWithETH{value: ownerQuote}(PredictionMarket.Outcome.YES, 0.1 ether);

        vm.prank(user);
        vm.expectRevert(PredictionMarket.PredictionMarket__AmountMustBeGreaterThanZero.selector);
        market.buyTokensWithETH{value: 0}(PredictionMarket.Outcome.YES, 0);
    }

    // Verifies buying reverts if the requested amount is larger than the market's current reserve.
    function test_buyTokensWithETH_revertsWhenLiquidityIsInsufficient() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__InsufficientLiquidity.selector);
        market.getBuyPriceInEth(PredictionMarket.Outcome.YES, 1 ether);
    }

    // Verifies selling returns ETH to the trader, moves tokens back into reserve, and reduces LP revenue.
    function test_sellTokensForEth_returnsEthAndUpdatesReserves() public {
        uint256 amountToTrade = 0.2 ether;
        uint256 costToBuy = _buyTokens(user, PredictionMarket.Outcome.YES, amountToTrade);
        uint256 sellPrice = market.getSellPriceInEth(PredictionMarket.Outcome.YES, amountToTrade);

        vm.startPrank(user);
        market.i_yesToken().approve(address(market), amountToTrade);
        market.sellTokensForEth(PredictionMarket.Outcome.YES, amountToTrade);
        vm.stopPrank();

        assertEq(market.i_yesToken().balanceOf(user), 0);
        assertEq(market.i_yesToken().balanceOf(address(market)), INITIAL_MARKET_RESERVE);
        assertEq(market.s_lpTradingRevenue(), costToBuy - sellPrice);
    }

    // Verifies selling fails when the trader lacks enough balance or allowance.
    function test_sellTokensForEth_revertsForInsufficientBalanceAndAllowance() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket.PredictionMarket__InsufficientBalance.selector, 0.1 ether, 0
            )
        );
        market.sellTokensForEth(PredictionMarket.Outcome.YES, 0.1 ether);

        _buyTokens(user, PredictionMarket.Outcome.YES, 0.1 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket.PredictionMarket__InsufficientAllowance.selector, 0.1 ether, 0
            )
        );
        market.sellTokensForEth(PredictionMarket.Outcome.YES, 0.1 ether);
    }

    // Verifies selling is blocked for the owner, after reporting, and for zero-amount trades.
    function test_sellTokensForEth_revertsForOwnerReportedAndZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__OwnerCannotCall.selector);
        market.sellTokensForEth(PredictionMarket.Outcome.YES, 0.1 ether);

        vm.prank(user);
        vm.expectRevert(PredictionMarket.PredictionMarket__AmountMustBeGreaterThanZero.selector);
        market.sellTokensForEth(PredictionMarket.Outcome.YES, 0);

        _buyTokens(user, PredictionMarket.Outcome.YES, 0.1 ether);

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        vm.startPrank(user);
        market.i_yesToken().approve(address(market), 0.1 ether);
        vm.expectRevert(PredictionMarket.PredictionMarket__PredictionAlreadyReported.selector);
        market.sellTokensForEth(PredictionMarket.Outcome.YES, 0.1 ether);
        vm.stopPrank();
    }

    // Verifies resolving before oracle reporting is blocked.
    function test_resolveMarketAndWithdraw_revertsIfNotReported() public {
        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__PredictionNotReported.selector);
        market.resolveMarketAndWithdraw();
    }

    // Verifies resolving after a YES outcome sends the owner remaining collateral plus accumulated fees.
    function test_resolveMarketAndWithdraw_sendsCollateralAndRevenueToOwner() public {
        uint256 tradingRevenue = _buyTokens(user, PredictionMarket.Outcome.YES, 0.2 ether);
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        vm.prank(owner);
        uint256 ethRedeemed = market.resolveMarketAndWithdraw();

        assertEq(ethRedeemed, 0.7 ether);
        assertEq(market.s_ethCollateral(), 0.3 ether);
        assertEq(market.s_lpTradingRevenue(), 0);
        assertEq(owner.balance, ownerBalanceBefore + 0.7 ether + tradingRevenue);
    }

    // Verifies resolving still works when the market contract holds no winning tokens and only trading fees remain.
    function test_resolveMarketAndWithdraw_handlesZeroWinningReserve() public {
        uint256 tradingRevenue = _buyTokens(user, PredictionMarket.Outcome.NO, INITIAL_MARKET_RESERVE);
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.NO);

        vm.prank(owner);
        uint256 ethRedeemed = market.resolveMarketAndWithdraw();

        assertEq(ethRedeemed, 0);
        assertEq(market.s_ethCollateral(), INITIAL_LIQUIDITY);
        assertEq(owner.balance, ownerBalanceBefore + tradingRevenue);
    }

    // Verifies winners can redeem their reported winning tokens for ETH at the fixed redemption value.
    function test_redeemWinningTokens_burnsTokensAndTransfersEth() public {
        _buyTokens(user, PredictionMarket.Outcome.YES, 0.5 ether);

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        uint256 userBalanceBefore = user.balance;
        uint256 winningTokens = market.i_yesToken().balanceOf(user);

        vm.prank(user);
        market.redeemWinningTokens(winningTokens);

        assertEq(market.i_yesToken().balanceOf(user), 0);
        assertEq(user.balance, userBalanceBefore + winningTokens);
        assertEq(market.s_ethCollateral(), INITIAL_LIQUIDITY - winningTokens);
    }

    // Verifies redemption is blocked before reporting, for the owner, for zero amounts, and for missing winning tokens.
    function test_redeemWinningTokens_revertsForInvalidCalls() public {
        vm.prank(user);
        vm.expectRevert(PredictionMarket.PredictionMarket__PredictionNotReported.selector);
        market.redeemWinningTokens(0.1 ether);

        vm.prank(oracle);
        market.report(PredictionMarket.Outcome.YES);

        vm.prank(owner);
        vm.expectRevert(PredictionMarket.PredictionMarket__OwnerCannotCall.selector);
        market.redeemWinningTokens(0.1 ether);

        vm.prank(user);
        vm.expectRevert(PredictionMarket.PredictionMarket__AmountMustBeGreaterThanZero.selector);
        market.redeemWinningTokens(0);

        vm.prank(user);
        vm.expectRevert(PredictionMarket.PredictionMarket__InsufficientWinningTokens.selector);
        market.redeemWinningTokens(0.1 ether);
    }

    function _deployMarket(
        uint256 initialLiquidity,
        uint256 initialTokenValue,
        uint8 initialYesProbability,
        uint8 percentageToLock
    ) internal returns (PredictionMarket deployedMarket) {
        vm.prank(owner);
        deployedMarket = new PredictionMarket{value: initialLiquidity}(
            owner, oracle, "Will it rain?", initialTokenValue, initialYesProbability, percentageToLock
        );
    }

    function _buyTokens(address buyer, PredictionMarket.Outcome outcome, uint256 amountToBuy)
        internal
        returns (uint256 ethNeeded)
    {
        ethNeeded = market.getBuyPriceInEth(outcome, amountToBuy);

        vm.prank(buyer);
        market.buyTokensWithETH{value: ethNeeded}(outcome, amountToBuy);
    }
}
