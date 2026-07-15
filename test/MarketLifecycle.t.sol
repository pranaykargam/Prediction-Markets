// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PredictionMarketToken} from "../src/PredictionMarketToken.sol";
import {AMMPool} from "../src/FifaAMMPool.sol";
import {PredictionMarket} from "../src/FifaPredictionMarket.sol";
import {MatchRegistry} from "../src/FifaTournamentRegistry.sol";
import {FifaOracleRouter} from "../src/FifaOracleRouter.sol";

contract MarketLifecycleTest is Test {
    address internal constant LP = address(0xA11CE);
    address internal constant TRADER = address(0xB0B);
    address internal constant ORACLE = address(0xCAFE);

    PredictionMarketToken internal usdc;
    PredictionMarketToken internal yes;
    PredictionMarketToken internal no;
    PredictionMarket internal market;
    FifaOracleRouter internal router;
    uint64 internal kickoff;

    function setUp() public {
        usdc = new PredictionMarketToken("Test USD Coin", "USDC", address(this));
        yes = new PredictionMarketToken("YES", "YES", address(this));
        no = new PredictionMarketToken("NO", "NO", address(this));
        MatchRegistry registry = new MatchRegistry(address(this));
        router = new FifaOracleRouter(address(registry), ORACLE);
        AMMPool pool = new AMMPool(address(usdc), address(yes), address(no), address(0), 30);
        kickoff = uint64(block.timestamp + 1 days);
        market = new PredictionMarket(
            address(usdc), address(yes), address(no), address(pool), address(router), 7, "Home", "Away", kickoff
        );
        pool.setMarket(address(market));
        yes.setMinter(address(market));
        no.setMinter(address(market));
        registry.registerMatch(7, "Home", "Away", kickoff, address(market));

        usdc.mint(LP, 1_000 ether);
        vm.startPrank(LP);
        usdc.approve(address(market), type(uint256).max);
        market.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether);
        vm.stopPrank();
    }

    function testTraderCanBuyAndRedeemWinningOutcome() public {
        usdc.mint(TRADER, 100 ether);
        vm.startPrank(TRADER);
        usdc.approve(address(market), type(uint256).max);
        market.buyYesWithUsdc(100 ether, 1);
        uint256 yesBalance = yes.balanceOf(TRADER);
        vm.stopPrank();

        assertGt(yesBalance, 0);
        vm.warp(kickoff);
        market.closeMarket();
        vm.prank(ORACLE);
        router.submitResult(7, 1);

        uint256 beforeBalance = usdc.balanceOf(TRADER);
        vm.prank(TRADER);
        market.redeemWinningTokens(yesBalance);
        assertEq(usdc.balanceOf(TRADER), beforeBalance + yesBalance);
        assertEq(yes.balanceOf(TRADER), 0);
    }

    function testTradingAndLiquidityRemovalStopAtKickoff() public {
        vm.warp(kickoff);
        vm.expectRevert("PredictionMarket: market not open");
        market.buyYesWithUsdc(1, 0);

        vm.prank(LP);
        vm.expectRevert("PredictionMarket: market not open");
        market.removeLiquidity(1);
    }

    function testLiquidityMustCreateFullyCollateralizedPairs() public {
        usdc.mint(TRADER, 100 ether);
        vm.startPrank(TRADER);
        usdc.approve(address(market), type(uint256).max);
        vm.expectRevert("PredictionMarket: unmatched outcomes");
        market.addLiquidity(100 ether, 100 ether, 99 ether);
        vm.expectRevert("PredictionMarket: insufficient collateral");
        market.addLiquidity(99 ether, 100 ether, 100 ether);
        vm.stopPrank();
    }
}
