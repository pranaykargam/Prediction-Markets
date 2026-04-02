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
}
